#!/usr/bin/env python3
"""Exercise the actual patched Wi-Fi roaming and last-connection bodies with a fake driver."""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent

def function(source, start):
    begin = source.index(start)
    end = source.index("\n}\n", begin) + 3
    return source[begin:end]

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("source", type=Path)
    a = p.parse_args()
    main = a.source.resolve() / "esp32-code/jooki_v2/main"
    sta, nvs = (main / "wcm_sta.c").read_text(), (main / "wcm_nvs.c").read_text()
    connect = function(sta, "static bool wcm_sta_connect_to_AP(int wifiConfigurationIndex) {")
    assert "cfg->sta.channel = 0;" in connect and "WIFI_FAST_SCAN" not in connect, "connect must not use the saved channel"
    assert "cfg->sta.scan_method = WIFI_ALL_CHANNEL_SCAN;" in connect and "WIFI_CONNECT_AP_BY_SIGNAL" in connect
    init = function(sta, "bool wcm_sta_init(void) {")
    assert "task_wcm_roam_func" in init, "the roaming task must be started"
    print("PASS every connection scans all channels and joins the strongest access point", flush=True)
    defines = "".join(m + "\n" for m in re.findall(r"^#define WCM_STA_(?:ROAM_\w+|MAXIMUM_SCAN_RESULTS_COUNT) .*$", sta, re.M))
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp)
        (out / "wifi_functions.inc").write_text(
            defines +
            function(sta, "static int wcm_sta_roam_pick(") +
            function(sta, "static bool wcm_sta_roam_connect(void) {") +
            function(sta, "static uint32_t wcm_sta_roam_check(void) {") +
            function(sta, "static void wcm_sta_station_event_handler(") +
            function(nvs, "void wcm_nvs_set_last_connected_ap_idx(int index_, int channel_) {"))
        subprocess.run(["cc", "-std=c99", "-D_DEFAULT_SOURCE", "-Wall", "-Wextra", "-Werror", "-Wno-unused-function", "-Wno-unused-parameter", "-g",
                        "-fsanitize=address,undefined", "-fno-sanitize-recover=all", "-I" + str(out),
                        str(HERE / "tests/wifi.c"), "-o", str(out / "wifi")], check=True)
        subprocess.run([str(out / "wifi")], check=True)

if __name__ == "__main__": main()
