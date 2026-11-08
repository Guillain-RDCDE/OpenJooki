#!/usr/bin/env python3
"""False-positive and input-integrity checks; no Spotify binary or device needed."""
import hashlib
import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location("spotify_offline_audit", Path(__file__).resolve().parents[1] / "spotify_offline_audit.py")
A = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(A)


def sources():
    return {
        "spotify_ctrl.c": '''
// SpRegisterStorageCallbacks() is only mentioned in this comment.
#define ESDK_VERSION "v3.156.25"
void init(void) {
  conf.product_id = 32;
  SpInit(&conf);
  log("SpPrefetchStart() is only a string, // not a source call");
}
struct cmd commands[] = {{"/j/spotify/output/play_preset", on_play}};
''',
        "spotify_embedded.h": '''
#define SP_API_VERSION 63
enum SpError { kSpAlreadyPrefetching = 1008, kSpStorageWriteError = 1010 };
/* SP_EMB_PUBLIC SpError SpPrefetchStart(void); */
SP_EMB_PUBLIC SpError
SpPlayPreset(int preset_id);
''',
        "ml-j2000/machine.h": '#define MODEL_NAME "J2000"\n',
        "CMakeLists.txt": "# requires ml-j2000/libspotify_embedded_static.a\n",
        "README.md": "The SDK library must be supplied separately.\n",
    }


class SpotifyEvidenceTests(unittest.TestCase):
    def test_error_names_comments_and_strings_are_not_offline_interfaces(self):
        result = A.inventory(sources(), library_present=False)
        self.assertEqual(result["offline_support"], "unresolved")
        self.assertEqual(result["header"]["offline_related_error_constants"],
                         ["kSpAlreadyPrefetching", "kSpStorageWriteError"])
        self.assertEqual(result["header"]["offline_related_function_declarations"], [])
        self.assertEqual(result["header"]["public_function_count"], 1)
        self.assertEqual(result["controller"]["offline_related_sdk_calls"], [])
        self.assertEqual(result["controller"]["sdk_function_calls"], ["SpInit"])
        self.assertEqual(result["controller"]["mqtt_commands"], ["/j/spotify/output/play_preset"])

    def test_even_declared_interfaces_and_library_are_not_support_proof(self):
        files = sources()
        # Invented test names, not proposed Spotify SDK APIs.
        files["spotify_embedded.h"] += '''
SP_EMB_PUBLIC SpError SpTestPrefetch(void);
typedef int (*SpTestStorageCallback)(void *context);
'''
        result = A.inventory(files, library_present=True)
        self.assertEqual(result["header"]["offline_related_function_declarations"], ["SpTestPrefetch"])
        self.assertEqual(result["header"]["offline_related_callback_types"], ["SpTestStorageCallback"])
        self.assertEqual(result["offline_support"], "unresolved")

    def test_incomplete_sources_do_not_produce_an_assessment(self):
        files = sources()
        files["spotify_ctrl.c"] = ""
        with self.assertRaisesRegex(ValueError, "eSDK version"):
            A.inventory(files, library_present=False)

    def test_bad_checksum_is_rejected_before_reading_archive(self):
        with tempfile.TemporaryDirectory() as folder:
            archive = Path(folder) / "archive.tgz"
            archive.write_bytes(b"not the official release")
            with patch.object(A.tarfile, "open", side_effect=AssertionError("must check SHA first")):
                with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                    A.audit(archive)
            self.assertEqual(list(Path(folder).iterdir()), [archive])

    def test_archive_is_inventoried_without_extracting_or_writing_files(self):
        with tempfile.TemporaryDirectory() as folder:
            archive = Path(folder) / "fixture.tgz"
            with tarfile.open(archive, "w:gz") as bundle:
                for name, text in sources().items():
                    data = text.encode()
                    member = tarfile.TarInfo(A.PREFIX + name)
                    member.size = len(data)
                    bundle.addfile(member, io.BytesIO(data))
            original = archive.read_bytes()
            with patch.object(A, "ARCHIVE_SHA256", hashlib.sha256(original).hexdigest()):
                result = A.audit(archive)
            self.assertFalse(result["controller"]["sdk_library_in_archive"])
            self.assertEqual(result["controller"]["esdk_version_from_source"], "v3.156.25")
            self.assertEqual(result["controller"]["header_api_version"], 63)
            self.assertEqual(result["source_sha256"]["spotify_ctrl.c"],
                             hashlib.sha256(sources()["spotify_ctrl.c"].encode()).hexdigest())
            self.assertEqual(archive.read_bytes(), original)
            self.assertEqual(list(Path(folder).iterdir()), [archive])


if __name__ == "__main__":
    unittest.main()
