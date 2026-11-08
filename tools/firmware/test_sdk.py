#!/usr/bin/env python3
"""Exercise the public-SDK port's actual transmit/reset bodies with DMA ownership fault injection."""
import argparse
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent

def function(source, signature):
    start = source.index(signature + " {")
    end = source.index("\n}\n", start) + 3
    return source[start:end]

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("source", type=Path)
    a = p.parse_args()
    main = a.source.resolve() / "esp32-code/jooki_v2/main"
    assert (main / "sdio_tx.h").read_bytes() == (HERE / "port/sdio_tx.h").read_bytes(), "build and test port headers differ"
    source = (main / "sdio_if.c").read_text()
    assert "sdio_slave_transmit_timeout(" not in source
    assert "&(buf_handle->payload_len), pdMS_TO_TICKS(50))" in source, "RX must yield its lock for reset"
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp)
        (out / "sdio_functions.inc").write_text(function(source, "static void sdio_write(interface_buffer_handle_t *buf_handle)") +
                                                function(source, "static esp_err_t sdio_reset()"))
        subprocess.run(["cc", "-std=c99", "-D_DEFAULT_SOURCE", "-Wall", "-Wextra", "-Werror", "-g", "-fsanitize=address,undefined",
                        "-I" + str(HERE / "tests/sdk_stubs"), "-I" + str(HERE / "port"), "-I" + str(out),
                        "-I" + str(main), "-I" + str(main.parent / "api"), str(HERE / "tests/sdio.c"), "-o", str(out / "sdio")], check=True)
        subprocess.run([str(out / "sdio")], check=True)

if __name__ == "__main__": main()
