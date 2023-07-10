+++
title = "Update your ABB Terra AC Wallbox"
subtitle = "No, really, it's pretty serious."
date = "2023-05-17"
lastmod = "2023-07-10T12:00:00+00:00"
slug = "pretacc"
+++

ABB, with the assistance of myself, [puck](http://puck.moe/), and an unrelated party, are today releasing an urgent [security advisory](https://search.abb.com/library/Download.aspx?Action=Launch&DocumentID=9AKK108468A1415&DocumentPartId=&LanguageCode=en) and adjacent firmware update for all _ABB Terra AC Wallbox_ Electric Vehicle Supply Equipment (EVSE). The vulnerability this refers to is known to affect all _ABB Terra AC Wallboxes_ in circulation up to and including version _v1.6.5_. Affected Wallboxes have serial numbers starting _TACW_, and model numbers starting either _W4-_, _W7-_, _W11-_, or _W22-_.

An attacker armed with knowledge of this vulnerability is able to connect with administrator privileges (also known as _TerraConfig_) to any Wallbox in Bluetooth range, with no physical access required whatsoever. They can then gain full control over the EVSE, including changing its connected OCPP server, instantiating a free vend, or modifying electrical safety parameters, among other things.

This vulnerability cannot be mitigated, except by updating to a newer firmware version. **If you are running _v1.6.5_ or lower, you are vulnerable, and need to upgrade as soon as possible!**

In particular, **I urge installers of EV charge points to encourage both current and historic customers to update, or consider a programme of updating chargers urgently where permitted by support contracts.**

## How to Upgrade

**The patched firmware version as of writing is v1.6.6.** On some models this varies - see below.

For those managing deployments over OCPP, please either talk to your ABB representative (you should already have been contacted), or patch as you have done for prior releases.

For those using the mobile app - **There are new ChargerSync and TerraConfig mobile apps - you need to switch to the new version to update, and when you do, the old ones will stop working.** These are as follows:

**Android:**
* **[ChargerSync](https://play.google.com/store/apps/details?id=com.abbemobility.chargersync)** (for end users)
* [TerraConfig](https://play.google.com/store/apps/details?id=com.abbemobility.terraconfig) (for installers)

**iOS:**
* **[ChargerSync](https://apps.apple.com/gb/app/chargersync/id6443737188)** (for end users)
* [TerraConfig](https://apps.apple.com/gb/app/terraconfig/id6443887124) (for installers)

Please note: Some model variants of Wallbox use different versioning. The patched version for these is as follows:

* UL40/80A: v1.5.6
* CE, PTB: v1.5.26
* CE, Symbiosis: v1.2.8

If you're unsure, you almost definitely need to be targetting v1.6.6.

## Full Disclosure

You can find a full write-up on **BLUTACC** [here]({{< ref "/blog/3_blutacc" >}}).

~~In the spirit of responsible disclosure, we will be publishing full details of the vulnerability (which we have codenamed **BLUTACC**), alongside a healthily long writeup of how we found it, in the coming weeks once everyone has had opportunity to patch.~~

**I cannot stress strongly enough that this is seriously urgent for anyone affected** - please take 15 minutes out of your day to get it done as soon as possible.

[CVE-2023-0863](https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2023-0863) Authentication Bypass **8.8 High**
[CVE-2023-0864](https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2023-0864) Plaintext Communication of Configuration Data **7.1 High**