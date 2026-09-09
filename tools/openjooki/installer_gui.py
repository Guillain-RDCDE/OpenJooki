#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
OpenJooki — "zero-level" graphical installer.
Explicit LIGHT palette on every widget (the Tk shipped by macOS does not handle
dark mode: without explicit colors, the text becomes invisible). Home-made
progress bar (tk.Frame) for reliable rendering everywhere. No dependencies.
"""
import os, sys, threading, queue, traceback
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tkinter as tk
from tkinter import filedialog, messagebox
import jooki
import installer

BG   = "#f4f5f7"   # window background
CARD = "#ffffff"   # cards
INK  = "#1b1f27"   # primary text
SUB  = "#6b7280"   # secondary text
LINE = "#d7dae0"   # lines / bar background
GREEN= "#1a7f37"; RED = "#b3261e"; WARN = "#9a6700"
ACC  = "#2f7d5b"; ACC2 = "#3aa76d"


class App:
    def __init__(self, root, preset_file=None):
        self.root = root
        self.q = queue.Queue()
        self.host = jooki.DEFAULT_HOST
        self.firmware = preset_file if (preset_file and os.path.isfile(preset_file)) else None
        self.busy = False
        self._host_ok = False

        root.title("OpenJooki — Safe installation")
        root.configure(bg=BG)
        root.geometry("640x560"); root.minsize(600, 540)

        wrap = tk.Frame(root, bg=BG); wrap.pack(fill="both", expand=True, padx=22, pady=20)

        tk.Label(wrap, text="OpenJooki", bg=BG, fg=INK,
                 font=("Helvetica", 24, "bold")).pack(anchor="w")
        tk.Label(wrap, text="Install a firmware completely safely — you cannot brick your Jooki.",
                 bg=BG, fg=SUB, font=("Helvetica", 12)).pack(anchor="w", pady=(2, 12))

        card = tk.Frame(wrap, bg=CARD, highlightbackground=LINE, highlightthickness=1)
        card.pack(fill="x")
        r1 = tk.Frame(card, bg=CARD); r1.pack(fill="x", padx=16, pady=(14, 6))
        tk.Label(r1, text="Jooki:", bg=CARD, fg=INK, width=9, anchor="w",
                 font=("Helvetica", 13)).pack(side="left")
        self.host_var = tk.StringVar(value=self.host)
        tk.Entry(r1, textvariable=self.host_var, width=17, font=("Helvetica", 13),
                 bg="white", fg=INK, highlightbackground=LINE).pack(side="left")
        tk.Button(r1, text="Check", command=self.check_host,
                  highlightbackground=CARD).pack(side="left", padx=8)
        self.host_status = tk.Label(r1, text="…", bg=CARD, fg=SUB, font=("Helvetica", 12))
        self.host_status.pack(side="left")
        r2 = tk.Frame(card, bg=CARD); r2.pack(fill="x", padx=16, pady=(6, 14))
        tk.Label(r2, text="Firmware:", bg=CARD, fg=INK, width=9, anchor="w",
                 font=("Helvetica", 13)).pack(side="left")
        tk.Button(r2, text="Choose the file…", command=self.pick_file,
                  highlightbackground=CARD).pack(side="left")
        self.file_lbl = tk.Label(r2, text="(no file)", bg=CARD, fg=SUB, font=("Helvetica", 12))
        self.file_lbl.pack(side="left", padx=8)

        self.go = tk.Button(wrap, text="Install safely", command=self.on_go,
                            state="disabled", font=("Helvetica", 15, "bold"),
                            highlightbackground=BG)
        self.go.pack(fill="x", pady=(16, 10))

        self.step_lbl = tk.Label(wrap, text="Ready.", bg=BG, fg=INK, font=("Helvetica", 13), anchor="w")
        self.step_lbl.pack(fill="x")
        bar = tk.Frame(wrap, bg=LINE, height=16); bar.pack(fill="x", pady=(4, 10))
        bar.pack_propagate(False)
        self.pbar_fill = tk.Frame(bar, bg=ACC); self.pbar_fill.place(x=0, y=0, relheight=1, relwidth=0)

        logwrap = tk.Frame(wrap, bg=BG); logwrap.pack(fill="both", expand=True)
        self.log = tk.Text(logwrap, height=10, font=("Menlo", 11), wrap="word",
                           bg="white", fg="#222", highlightbackground=LINE, bd=1, relief="solid")
        sb = tk.Scrollbar(logwrap, command=self.log.yview)
        self.log.configure(yscrollcommand=sb.set)
        sb.pack(side="right", fill="y"); self.log.pack(side="left", fill="both", expand=True)
        self.log.configure(state="disabled")

        self.banner = tk.Label(wrap, text="", bg=BG, fg=INK, font=("Helvetica", 13, "bold"), anchor="w")
        self.banner.pack(fill="x", pady=(8, 0))

        self._refresh_file_label()
        self._poll()
        self.root.after(300, self.check_host)

    def _set_prog(self, p):
        self.pbar_fill.place_configure(relwidth=max(0.0, min(1.0, p / 100.0)))

    def _log(self, msg):
        self.log.configure(state="normal")
        self.log.insert("end", msg + "\n"); self.log.see("end")
        self.log.configure(state="disabled")

    def _refresh_file_label(self):
        if self.firmware:
            try:
                sz = installer.human(installer._uncompressed_size(self.firmware))
            except Exception:
                sz = "?"
            gz = " (compressed)" if self.firmware.endswith(".gz") else ""
            self.file_lbl.config(text="%s — %s%s" % (os.path.basename(self.firmware), sz, gz), fg=INK)
        else:
            self.file_lbl.config(text="(no file)", fg=SUB)
        self._update_go()

    def _update_go(self):
        ready = (self.firmware is not None) and self._host_ok and not self.busy
        self.go.config(state=("normal" if ready else "disabled"))

    def pick_file(self):
        if self.busy:
            return
        p = filedialog.askopenfilename(
            title="Choose the OpenJooki firmware",
            filetypes=[("Firmware", "*.img *.ext4 *.gz *.bin"), ("All files", "*.*")])
        if p:
            self.firmware = p
            self._refresh_file_label()

    def check_host(self):
        if self.busy:
            return
        self.host = self.host_var.get().strip() or jooki.DEFAULT_HOST
        self.host_status.config(text="searching…", fg=SUB)
        threading.Thread(target=self._check_host_worker, daemon=True).start()

    def _check_host_worker(self):
        try:
            ok = jooki.is_jooki(self.host)
        except Exception:
            ok = False
        self.q.put(("host", ok))

    def on_go(self):
        if self.busy or not self.firmware:
            return
        try:
            sz = installer.human(installer._uncompressed_size(self.firmware))
        except Exception:
            sz = "?"
        if not messagebox.askyesno(
                "Confirm the installation",
                "Install this firmware on your Jooki?\n\n"
                "File: %s\nSize: %s\n\n"
                "• Written to the spare partition (the current one stays intact).\n"
                "• Transfer verified bit for bit.\n"
                "• The Jooki reboots once; if it does not boot, it returns\n"
                "  on its own to the current version.\n\n"
                "Do not unplug during the operation."
                % (os.path.basename(self.firmware), sz)):
            return
        self.busy = True; self._update_go()
        self.go.config(text="Installation in progress…")
        self.banner.config(text="", fg=INK)
        self._set_prog(0)
        threading.Thread(target=self._install_worker, daemon=True).start()

    def _install_worker(self):
        try:
            res = installer.install_firmware(
                self.host, self.firmware,
                on_step=lambda m: self.q.put(("step", m)),
                on_progress=lambda p: self.q.put(("prog", p)))
            self.q.put(("done", res))
        except installer.InstallError as e:
            self.q.put(("fail", str(e)))
        except Exception as e:
            self.q.put(("step", traceback.format_exc()))
            self.q.put(("fail", "Unexpected error: %s" % e))

    def _poll(self):
        try:
            while True:
                kind, payload = self.q.get_nowait()
                if kind == "host":
                    self._host_ok = payload
                    self.host_status.config(text=("online ✓" if payload else "not found ✕"),
                                            fg=(GREEN if payload else RED))
                    self._update_go()
                elif kind == "step":
                    self.step_lbl.config(text=payload if len(payload) < 78 else payload[:77] + "…")
                    self._log(payload)
                elif kind == "prog":
                    self._set_prog(payload)
                elif kind == "done":
                    self._finish(payload)
                elif kind == "fail":
                    self._finish_fail(payload)
        except queue.Empty:
            pass
        self.root.after(120, self._poll)

    def _finish(self, res):
        self.busy = False; self.go.config(text="Install safely"); self._update_go()
        if res.get("ok") and res.get("switched"):
            self._set_prog(100)
            self.banner.config(text="✓  Done — your Jooki is running on the new firmware.", fg=GREEN)
        elif res.get("ok"):
            self.banner.config(text="✓  Firmware written and verified (not activated).", fg=GREEN)
        else:
            self.banner.config(text="↩  The new version did not boot — automatic rollback. Nothing broken.",
                               fg=WARN)

    def _finish_fail(self, msg):
        self.busy = False; self.go.config(text="Install safely"); self._update_go()
        self._log("FAILED: " + msg)
        self.step_lbl.config(text="Stopped without breaking anything.")
        self.banner.config(text="⚠  " + (msg if len(msg) < 88 else msg[:86] + "…"), fg=RED)
        messagebox.showwarning("Installation stopped", msg + "\n\nYour Jooki was not modified.")


def main():
    preset = sys.argv[1] if len(sys.argv) > 1 else None
    root = tk.Tk()
    try:
        App(root, preset)
        root.lift()
        root.attributes("-topmost", True)
        root.after(700, lambda: root.attributes("-topmost", False))
    except Exception:
        messagebox.showerror("OpenJooki", "Startup error:\n" + traceback.format_exc())
        raise
    root.mainloop()


if __name__ == "__main__":
    main()
