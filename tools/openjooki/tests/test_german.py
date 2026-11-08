"""German device UI on the real core, including narrow layout, characters, pictures and storage."""
import os
from playwright.sync_api import sync_playwright
import bench as B
from jk import PAGE

R = B.Results()
j = B.boot(ui=True)
j.nfc("04000000F00001", "101"); j.nfc_off()
j.nfc("04A1B2C3D49C41", "200"); j.nfc_off()
with sync_playwright() as pw:
    browser = pw.chromium.launch(args=["--no-sandbox"])
    ctx = browser.new_context(locale="de-DE", viewport={"width": 375, "height": 812})
    pg = ctx.new_page(); errors = []
    pg.on("pageerror", lambda e: errors.append(str(e)))
    pg.goto(PAGE + "/#/settings"); pg.wait_for_selector("[data-k=langnav]")
    R.check("German browser detected", pg.locator("html").get_attribute("lang") == "de" and pg.locator("h1").inner_text() == "Einstellungen")
    for key in ("heartpress", "knobmode"):
        width = pg.locator("[data-k=" + key + "]").evaluate("el => el.closest('.srow').querySelector('.lbl').getBoundingClientRect().width")
        R.check("readable narrow label " + key, width >= 180, width)
    for route in ("settings", "settings/language", "settings/night", "settings/bluetooth", "settings/wifi", "tokens", "library", "playlists"):
        pg.goto(PAGE + "/#/" + route); pg.wait_for_selector("h1")
        R.check("narrow layout " + route, pg.evaluate("() => document.documentElement.scrollWidth <= innerWidth"))
    pg.goto(PAGE + "/#/tokens"); pg.wait_for_selector("[data-char='Jooki.Fox']")
    R.check("German figure name", "Fuchs" in pg.locator("[data-char='Jooki.Fox']").inner_text())
    pg.locator("[data-char='flat.04A1B2C3D49C41']").click(); pg.click("[data-k=libpick]")
    pg.wait_for_selector("[data-libcat=animals]")
    R.check("German picture category", pg.get_attribute("[data-libcat=animals]", "aria-label") == "Tiere")
    pg.fill("[data-k=imgq]", "Katze"); pg.wait_for_selector("[data-img=cat]")
    R.check("German picture name and search", pg.locator("[data-img=cat]").inner_text() == "Katze")
    pg.click("[data-k=libcancel]"); pg.click("[data-k=charclose]")
    pg.goto(PAGE + "/#/settings/language"); pg.click("[data-k=lang-de]")
    pg.reload(); pg.wait_for_selector("[data-k=lang-de]")
    R.check("German persists after reload", pg.evaluate("() => localStorage.getItem('oj.lang')") == "de" and pg.locator("html").get_attribute("lang") == "de")
    pg.click("[data-k=lang-en]"); pg.reload(); pg.wait_for_selector("h1:text-is('Language')")
    R.check("saved choice overrides German browser", pg.locator("html").get_attribute("lang") == "en")
    R.check("no JavaScript errors", not errors, errors)
    os.makedirs("shots", exist_ok=True)
    pg.click("[data-k=lang-de]"); pg.goto(PAGE + "/#/settings"); pg.wait_for_selector("[data-k=langnav]")
    pg.evaluate("() => scrollTo(0,0)"); pg.screenshot(path="shots/german-settings.png")
    browser.close()
B.check_clean_log(R, "German UI")
j.close(); R.finish()
