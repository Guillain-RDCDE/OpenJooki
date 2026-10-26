# Questions

**Will I lose my music or my tokens?**
No. They live on a part of the Jooki that updates never touch.

**What if something goes wrong?**
Switch the Jooki off and on again: it goes back to the previous version by itself.

**My Jooki does not start at all, whatever I do.**
Nine times out of ten its memory card (the SD card inside it) is dead.
[A new card](https://guillain-rdcde.github.io/OpenJooki/sdcard.html#new) brings it back;
the music has to be added again.

**Can I go back to the original Jooki?**
Yes: the [SD card tool](https://guillain-rdcde.github.io/OpenJooki/sdcard.html#original)
makes a card with the Jooki exactly as it was sold, without OpenJooki. Keep the Jooki's own
card: it is your way back. But the official app and Jooki's servers are gone, so the
original program can no longer be set up from a phone.

**Can anyone outside my home see my Jooki?**
No. No account, no cloud, no tracking.

**After switching it on, the Wi-Fi takes a minute or two.**
That's normal: about a minute and a half. Tokens and music work in the meantime.

**It restarted by itself, without its little chime.**
That's OpenJooki getting the Wi-Fi back. When the Jooki has had no Wi-Fi for ten minutes,
is on the charger and plays nothing, it restarts quietly (twice in a row at most).

**It is on the Wi-Fi at the other end of the house.**
The Jooki does not pick the strongest Wi-Fi: after a short cut it can move to another one
it knows and stay there. Keep only the Wi-Fi next to it: on the
[Wi-Fi page](https://guillain-rdcde.github.io/OpenJooki/wifi.html), find the Jooki,
**Forget** every network in *Networks the Jooki remembers*, then give it the Wi-Fi next to it
again. Forgetting does not cut its Wi-Fi.

**It only gets on the Wi-Fi after I use the Wi-Fi page.**
After every start the side dots stay orange until you give it a network on the
[Wi-Fi page](https://guillain-rdcde.github.io/OpenJooki/wifi.html). At start the Jooki only
looks at the networks before the first empty slot, and OpenJooki 2.0.9 to 2.4.2 forgot
Muuselabs' own network, which sat in the first slot. On the Wi-Fi page, **Forget** every network,
then give it your Wi-Fi once more: it then finds it by itself at every start.

**On holiday, night mode does nothing.**
Without the Internet the Jooki does not know the time. Open its page once from your phone:
it takes your phone's time. [Away from home](travel.md).

**Why can't I reconnect the Wi-Fi from my iPhone?**
A Jooki without Wi-Fi only listens over Bluetooth, and Apple does not let any web page use
Bluetooth on an iPhone or iPad, in any browser. That one step takes an Android phone or a
computer with Chrome or Edge, once; everything else works from the iPhone.

**I installed OpenJooki, but I still see the old Jooki page.**
The old page has a menu on the left (*Playlists*, *Tokens*, *Parental controls*, *Device info*).
OpenJooki's page has four tabs at the bottom, and **Settings** is the last one.
First close the old page for good: close the browser tab, or if it is an icon on your home
screen, swipe it away from the list of open apps. Then open the address again, in a new tab.
Still the old page? Open the address followed by `/openjooki-status.txt` (like
`http://192.168.1.19/openjooki-status.txt`): it is what the installer wrote, and its last line
says how it ended. No such page means the install never started: do it again.
If you're stuck, send me that text: guillain@poulpe.us.

**What is the address of my Jooki's page?**
`http://` followed by the address your internet box shows for it (like `http://192.168.1.19`),
or by its name and `.local`. Its name is `jooki2-…` until you give it another one: in
*Settings*, tap **Rename**. With the name `jooki`, the page is at `http://jooki.local`.

**Can I add a whole album at once?**
Yes, from a computer: **Add albums**, or drop the album's folder on the page. On a phone,
add the songs with **Add files**. [Use it](use.md).

**Does Spotify work? And Deezer?**
Spotify does: choose the Jooki in the Spotify app ([Use it](use.md#spotify)). Deezer does
not.

**A token stops the Spotify music on another speaker at home. Why?**
The Jooki plays tokens on its own Spotify account, the first one that set it up. If someone
listens to that same account on another speaker, Spotify stops it: one account plays in one place
at a time. In *Settings → Spotify*, tap **Change the Jooki's account**, then pick the Jooki in the
Spotify app from the account the tokens should use ([Use it](use.md#spotify)).

**My Spotify tokens stopped playing, after someone "forgot" the Jooki in the Spotify app.**
In the Spotify app, *Forget this device* on the Jooki removes the Jooki's own account, whichever
account does it. Pick the Jooki again in the Spotify app, from the account the tokens should use:
it becomes the Jooki's account again ([Use it](use.md#spotify)).

**What are *Home automation* and *Maintenance access* in Settings?**
Two switches for tinkerers. Leave them off.

**And the Jooki 1?**
It's on the way, but it's a much more closed box: it takes more work.

**Who makes this?**
A parent, for his own children first. Free, not affiliated with Muuselabs / Jooki.
Contact: guillain@poulpe.us

[← Back](../README.md)
