# VPS setup for MuaynyGoldEA

A VPS keeps MT5 running 24/5 with a stable connection to your broker's server. This matters because:

- Gold gaps over the weekend and trends hard during low-liquidity hours — an EA that is offline misses signals or, worse, holds a position with no stop management.
- Home internet drops are silent until you check. A VPS in the same region as your broker's server typically gives you sub-50ms latency.
- Power cuts don't take the EA down with your laptop.

## Choosing a VPS

What matters, in order:

1. **Location.** Same region as your broker's data center. For most retail XAUUSD brokers this is London (Equinix LD4/LD5) or New York. Check your broker's website — they often state which DC they use, sometimes offer free VPS hosting through partners.
2. **Latency to broker.** After signup, ping your broker's MT5 server from the VPS. Target < 30ms. Above 100ms means slippage on entries.
3. **RAM/CPU.** MT5 with one EA needs ~1 GB RAM and 1 vCPU. Get 2 GB / 2 vCPU to avoid swapping. Don't overpay for 8+ GB unless you run 5+ MT5 instances.
4. **Uptime guarantee.** 99.9% is the floor.
5. **Reboot policy.** Some cheap providers do unannounced reboots. Read reviews.

Common options (no endorsement, do your own due diligence): broker-bundled VPS (e.g., ICMarkets/Pepperstone free VPS if you meet volume), Forex VPS (forexvps.net), Vultr/Hetzner/Contabo (cheap but generic — you handle MT5 install).

## One-time setup (Windows VPS)

1. **Connect.** Use Microsoft Remote Desktop on Mac / Windows / iOS. Save the credentials.
2. **Install MT5.** Download the installer from your broker's site (not metaquotes directly — broker builds include their server list). Install to `C:\Program Files\YourBroker MT5`.
3. **Log in to your trading account.** File → Login to Trade Account. Tick "Save account information" so MT5 reconnects after reboot.
4. **Settings:**
   - Tools → Options → Server: tick **"Enable DDE server"** OFF, **"Enable WebRequest for listed URL"** OFF (unless your EA needs it — this one does not).
   - Tools → Options → Expert Advisors: tick **"Allow algorithmic trading"** and **"Allow DLL imports"** OFF (this EA needs no DLLs).
5. **Install the EA.**
   - File → Open Data Folder (this opens the VPS's MT5 data folder).
   - Copy `MQL5/Experts/MuaynyGoldEA.mq5` into `MQL5/Experts/`.
   - Copy `MQL5/Presets/MuaynyGoldEA_XAUUSD_default.set` into `MQL5/Presets/`.
   - Back in MT5: Navigator → Expert Advisors → right-click MuaynyGoldEA → Compile. Confirm `0 errors`.
6. **Attach to chart.**
   - Open XAUUSD chart, set timeframe to M15.
   - Drag MuaynyGoldEA onto the chart. Common tab: tick **"Allow Algo Trading"**. Inputs tab: click **Load** → pick `MuaynyGoldEA_XAUUSD_default.set`.
   - Confirm the smiley face in the chart's top-right is happy (not sad/crossed).
7. **Confirm AutoTrading on globally.** Toolbar button is green.
8. **Save profile.** File → Profiles → Save As → "Gold-Live". Reload it after restarts so charts and EAs come back.

## Auto-restart after reboots

Windows VPS providers reboot for patches monthly. To survive:

1. **Auto-login.** Set up Windows auto-login (`netplwiz` → untick "Users must enter a username and password"). Required so the desktop session is live for MT5 to attach.
2. **Auto-start MT5.** Right-click the MT5 shortcut → Properties → copy. Paste into `shell:startup` (Win+R → `shell:startup`). MT5 will launch on boot.
3. **Re-attach EA on launch.** MT5 remembers the last open profile if you check **"Save profile on exit"** under Tools → Options → Charts. Combined with step 6 above, the EA reattaches automatically.

## Monitoring

Don't sit on the VPS all day. Set up two channels:

- **Push notifications from MT5.** Tools → Options → Notifications → enable, paste your MetaQuotes ID from the mobile MT5 app. The EA's `Print()` statements appear in the Experts log but won't push. For trade events MT5's built-in account-side notifications cover open/close.
- **Daily eyeball.** Once a day RDP in and check: balance, equity, open positions, Experts tab for errors, journal for connection drops.

## When to disable the EA

- **Major scheduled news** (FOMC, NFP, CPI) — even if you trust the daily-loss circuit breaker, spreads widen to 500+ points around these and slippage is brutal. Disable AutoTrading 5 minutes before / 10 minutes after. The dynamic spread filter and the `InpMaxSpreadHardPts` cap block most news-spike entries automatically, but manual disabling is still the safe choice.
- **Anything weird in the journal:** "Connection lost", "Trade context busy", "Invalid stops" repeated > 5 times in a row. Disable, investigate, re-enable.
- **Broker maintenance.** Most brokers post weekend maintenance windows. The EA's weekend filter handles Sat/Sun but not always Sunday-evening server resets.

## Cost expectation

- VPS: $10-30/month for a basic Windows VPS suitable for one MT5 instance.
- Some brokers reimburse VPS cost if you trade > 5 lots/month. Ask.

## Linux VPS? Wine?

Possible but not recommended. MT5 under Wine has historically had subtle issues with timezones, file locking, and disconnect handling that bite at the worst moments. If you need Linux, run MT5 in a Windows VM on top.
