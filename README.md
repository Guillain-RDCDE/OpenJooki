![OpenJooki](docs/img/openjooki-social.png)

# OpenJooki

**Your child's Jooki keeps working, even though the Jooki company and its servers are gone.**

Your music stays, the tokens keep working, and you get a simple page to manage
everything from your phone. Nothing leaves your home, and it is built so that it
**cannot break your Jooki**.

> Independent community project, not affiliated with Muuselabs / Jooki.

![The OpenJooki page on a phone](docs/img/openjooki-web.png)

## What you get

- **Your music, from your phone**: create playlists and add songs straight from
  your phone, and choose which character starts which playlist.
- **Bedtime made easy**: audiobooks pick up where your child fell asleep, a sleep
  timer that fades out gently, and a night mode that keeps the volume low.
- **No account, no cloud**: everything stays on your home Wi‑Fi.
- **Updates in one tap**, from the Jooki's own page.

## Install it (10 minutes, from your phone)

You need a **Jooki v2**, switched on and **plugged in**, and a **phone on the same Wi‑Fi**.

1. **Find your Jooki's address.** Open your internet box's app or page, look at the
   connected devices, and find the one whose name starts with **jooki**. Its address
   looks like `192.168.1.19`.
2. On your phone, open **https://guillain-rdcde.github.io/OpenJooki/**, type that
   address and tap **Install OpenJooki**.
3. **Wait.** The Jooki installs everything by itself and restarts on its own (about
   10–15 minutes). Nothing happens on screen meanwhile: that's normal. Don't unplug it.

Not sure it's a v2? No risk: any other model is recognised and nothing happens.

## Use it

On your phone, type **`http://`** followed by your Jooki's address, for example
`http://192.168.1.19`, or its name, for example `http://jooki2-a1b2c3.local`
(the name is shown in the page's Settings). Don't forget the `http://`: without it,
some phones search the web instead.

Tip: add the page to your home screen to open it in one tap.

## Questions

- **Will I lose my music or my tokens?** No. They live on a part of the Jooki
  that updates never touch.
- **What if something goes wrong?** Unplug the Jooki and plug it back in: it goes
  back to the previous version by itself.
- **Can anyone outside my home see my Jooki?** No. No account, no cloud, no tracking.
- **Running out of space?** Move it to a bigger SD card with a Windows computer:
  [one file, nothing to install](tools/sdcard/README.md).

## Coming next

**OpenJooki 2.0** is being tested on a family Jooki: it starts faster, and you can
give your Jooki a name of your own (for example `http://jooki.local`). It will
arrive as a normal update.

## How it works

The plumbing (why it can't break a Jooki, installing from a computer, how the
Jooki was taken apart, the new core, the tools) is explained in
**[docs/](docs/README.md)**.

## Contact · License

Guillain d'Erceville — guillain@poulpe.us

MIT license. Built to be safe, but use it at your own risk.
