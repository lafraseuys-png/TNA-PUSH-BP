# TNA POS Edge

The installed till. The same POS screen as the browser, served by this PC, so selling
carries on when the internet is down and everything is sent to the server when it is back.

## For the shop (what the cashier's PC gets)
The ZIP from the POS screen's **Install App** button contains:

```
TNA-POS-Edge.exe        this program
pos-edge.config.json    company, server address, till and till key  (keep it private)
install.cmd             installs and starts it (run as administrator)
README.txt             short instructions
```

1. Extract to `C:\TNA-POS`
2. Right-click **install.cmd** → Run as administrator
3. Open **http://localhost:3099** in Chrome or Edge, then choose "Install app" in the address bar
4. Sign in with the normal username and password

## What it does
- **Online:** every screen and every sale goes to the company's server, exactly like the browser POS.
  It keeps a copy of the items, prices, employees, the open day and the settings.
- **Offline:** the till answers from that copy. Sales, returns, cash drops, paid outs, the day start,
  the cash-up and stock take counts are queued, with the **time they really happened** and a
  temporary slip number such as `OFF-T01-S0001`.
- **Back online:** the queue is sent in order. Each job carries its own reference, so nothing is
  recorded twice. The server gives each sale its normal number.
- **Sign-in offline:** the password is checked against the copy downloaded while online, so a cashier
  can start a shift even with no signal, as long as they have signed in on that till once before.
- **Anything the server refuses** (for example a wrong manager PIN entered offline) is parked in
  `data\failed.json` with the reason, instead of being retried forever.

## Where things are kept
```
data\cache.json      the last download from the server
data\outbox.json     work waiting to be sent
data\receipts.json   the last 200 slips
data\failed.json     jobs the server refused
data\edge.log        what the till has been doing
```

## Everyday use
- The pill at the bottom left of the POS screen shows **Online / Offline**, how many jobs are waiting
  and the till number. Tap it to sync straight away.
- `http://localhost:3099/edge/status` shows the same information as plain text.
- To move a till to another PC, download a new package for it in **POS Settings → Tills**.
  The old PC stops syncing, so finish and sync its work first.

## Removing it
Run `TNA-POS-Edge.exe --uninstall` as administrator.

## Building the exe
See `build.cmd`.
