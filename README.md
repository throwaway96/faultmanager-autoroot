# faultmanager-autoroot

> [!IMPORTANT]
> This was quickly adapted from
> [dejavuln-autoroot](https://github.com/throwaway96/dejavuln-autoroot) with
> limited testing. Expect it to be rough around the edges.

This is a tool to root LG TVs with webOS 3.5+ and automatically install
[Homebrew Channel](https://github.com/webosbrew/webos-homebrew-channel).
It uses a vulnerability in `faultmanager`
[discovered by buglloc](https://ut.buglloc.com/webos-jailbreak/).

I'm not sure which webOS versions are vulnerable. I have personally tested it
on webOS 4.5, 6, and 7. I don't expect it to work on versions older than 3.5,
as `faultmanager` is not present.

<!--
TODO: add back once this vulnerability is supported

> [!NOTE]
> Use [CanI.RootMy.TV](https://cani.rootmy.tv/) to determine whether your
> firmware is vulnerable.
-->

## Instructions

1. Set up
   [Developer Mode](https://webostv.developer.lge.com/develop/getting-started/developer-mode-app).
2. Connect to the TV with an SSH client. (If you need help, see the
   [crashd guide](https://gist.github.com/throwaway96/e811b0f7cc2a705a5a476a8dfa45e09f).)
3. Download `autoroot.sh` to any writable directory (e.g., `/tmp`).
4. Run `autoroot.sh` (e.g., `sh /tmp/autoroot.sh`).
5. After the `Rooting complete` message, hit control + C to exit.
6. **Before rebooting**, uninstall the LG Developer Mode app.

**Do not** install the LG Developer Mode app while the TV is rooted!

## Settings

The `autoroot.sh` script accepts certain command line options:

* `--debug` or `-d` - Enables additional logging.
* `--telnet` or `-t` - Makes a root shell available via telnet on port 23.
  Note that this won't work on webOS 9 (24), which does not have `telnetd`!

If there is a file named `hbchannel.ipk` in the same directory as
`autoroot.sh`, it will be installed. Otherwise, the latest Homebrew Channel
IPK will be downloaded and installed.

## Troubleshooting

On webOS 8/9 (webOS 23/24), you may have to try multiple times; it seems that
restarting `appinstalld` does not reliably make it detect the existence of
`devmode_enabled`. May also apply to webOS 7.

If the toast and/or log says "Rooting complete" but you don't see Homebrew
Channel, reboot the TV. Make sure Quick Start+ is disabled.

## Support

You can find more information at [webosbrew.org](https://www.webosbrew.org/).

If you need help rooting your TV, try the
[OpenLGTV Discord](https://discord.gg/hXMHAgJC5R). Before you ask a question,
check the FAQ (#faq) to see if it is answered there!
<!--
TODO: add back when logging is done

Attach your `autoroot.log` when asking for help.
-->

## Credits

* The vulnerability in `faultmanager` was discovered by
[@buglloc](https://github.com/buglloc)
([Andrew Krasichkov](https://buglloc.com/)).

## License

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU Affero General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option) any
later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License along
with this program. If not, see <https://www.gnu.org/licenses/>.

See `COPYING` for details.
