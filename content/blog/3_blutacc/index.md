+++
title = "BLUTACC"
subtitle = "Public disclosure of a vulnerability in ABB Terra AC EV charging equipment."
date = "2023-07-10T12:00:00+00:00"
slug = "blutacc"
section_title = "Goodness me, where to even start."
+++

**[BLUTACC](https://youtu.be/lG50yEvaDJE)** (**BLU**etooth **T**erra **AC** **C**ontrol) is a serious vulnerability in the Bluetooth Low Energy control interface of all _ABB Terra AC Wallbox_ Electric Vehicle Supply Equipment (EVSE), affecting up to and including version _v1.6.5_. Affected Wallboxes have serial numbers starting _TACW_, and model numbers starting either _W4-_, _W7-_, _W11-_, or _W22-_.

An attacker armed with knowledge of this vulnerability is able to connect with administrator privileges (also known as _TerraConfig_) to any Wallbox in Bluetooth range, with no physical access required whatsoever. They can then gain full control over the EVSE, including changing its connected OCPP server, instantiating a free vend, or modifying electrical safety parameters, among other things.

This vulnerability cannot be mitigated, except by updating to a newer firmware version. **If you are running _v1.6.5_ or lower, you are vulnerable, and need to upgrade immediately!**

**You can find more details on patching in my previous post [here]({{< ref "/blog/2_pretacc" >}})**.

Whilst this is being published today by myself alongside the manufacturer with assistance from Ars Technica, this would not have been possible without a huge amount of help from [puck](https://puck.moe), who assisted further dissection of firmware and app routines to properly understand the nature of this vulnerability.

_BLUTACC has been assigned CVE [CVE-2023-0863](https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2023-0863) with a CVSS 3.1 base score of **8.8 High** (8.2 Temporal)._

**Full technical information on the vulnerability, as well as the proof of concept control application written in _Go_, can be found at [https://github.com/duckfullstop/blutacc](https://github.com/duckfullstop/blutacc).**


For those using OCPP: once you are on v1.6.6, anyone attempting to use this exploit against a charger will trigger a `SecurityEventNotification` that looks like this:

```
{"type": "AttemptedReplayAttacks", "techInfo": "bleAttacks", "timestamp": "2023-07-10T12:00:00Z"}
```

___
The rest of this post is fairly long, and is going to go into the detail of how this vulnerability was found. If you're not interested in that bit, you can stop reading now and just pay attention to the bit above. If you're morbidly curious as to how we ended up figuring out this _extremely_ glaring hole in security, read on...
___

## Discovery

Back when an old acquaintance got an EV, they opted to have a _Terra AC_ installed - the particular model was a _TACW7-T-R-0_. They chose the Terra AC as it had exactly the features software engineering nerds like us were interested in:

* support for OCPP (Open Charge Point Protocol), allowing custom servers for tracking usage, home automation, etcetera
* RFID tag support for the true beep-boop charging experience that payments nerds crave
* good build quality, plain and simple design
* socketed variants available for those that need more specialist cables

OCPP is a surprisingly difficult feature to find: a lot of home oriented EVSE are cloud connected, which brings a whole host of issues to the table including privacy and security concerns, internet stability requirements, and problems if the manufacturer ever goes bust and pulls the service. OCPP is the standard protocol used by basically every major public charging service provider (and public charger!), including _Gridserve_, _Electrify America_, _Ionity_, and many many more, and it's a super-simple client-server design that anyone can interface with

If you've got a charger with OCPP, you've got tonnes of options for talking to it locally: you can integrate it with [Home Assistant](https://home-assistant-ocpp.readthedocs.io/en/latest/), offload excess solar energy to it using [EVCC (de)](https://docs.evcc.io/docs/devices/chargers#ocpp-16j-kompatible-wallbox-mit-smart-charging-profil), and if none of the off-the-shelf options work, you can write your own server based on the [public specification](https://www.oasis-open.org/committees/download.php/58944/ocpp-1.6.pdf).

So a couple of days after getting this wallbox installed, we start investigating how to get it hooked up with our Home Assistant installation. We get the plugin installed absolutely fine, but when it comes to getting the wallbox to talk to it, we hit a pretty major snag pretty freakin' quickly.

### TerraConfig, ChargerSync, and a lack of authority

To give some necessary context, we need to talk about the apps.

The _TerraConfig_ app (for iOS and Android) is intended for installing engineers and electricians to change fundamental configuration parameters - for example, they may wish to set a maximum amperage (so as to avoid overloading circuits), update firmware, configure Modbus load balancing, or set remote OCPP (Open Charge Point Protocol) server settings (for example, when configuring a public charge point). Access to this application is gated behind login credentials provided by ABB only to qualified electricians. Further, access to each charger is _supposed_ (wow, foreshadowing) to **require an 8 digit alphanumeric PIN code supplied with each _Terra AC_.** Full details on the _TerraConfig_ platform can be found in the [datasheet](https://www.mobilityhouse.com/media/productattachments/files/ABB_Terra_AC_Wallbox_Konfiguration.pdf) (thanks, The Mobility House, for hosting this one in an easily accessible location! feel free to reach out if you'd prefer I didn't hotlink)

End users are not intended to have this level of access, so ABB have a separate app called _ChargerSync_ for us mere mortals. This also connects via the Bluetooth Low Energy protocol, has its own registration system (which anyone can register for), and requires the same 8 digit alphanumeric PIN, but provides a cut-down interface - for example, the charging speed limit can only be set to a maximum of whatever the installer set during commissioning with _TerraConfig_, and new RFID cards to start charging must be ABB branded. This is intended for use by home-owners and the like who just need something to control basic functions.

As you can imagine with us being the tinkering type, _ChargerSync_ wasn't good enough - for some (honestly hard to understand) reason, OCPP configuration settings are only available through _TerraConfig_. So we started figuring out how to get ourselves a _TerraConfig_ account. My old acquaintance fired off an email, and the response wasn't good - **ABB refused to provide credentials for TerraConfig as we weren't qualified electricians.** Even after a bit of pleading, they still wouldn't budge on this requirement.

So we did what all frustrated nerds do - we set about reverse engineering how the app worked.

### Discovering BLUTACC
We decided that the best course of action was to look into reverse engineering the _TerraConfig_ app, extracting how it performed calls to the _Terra AC_, then either patching _ChargerSync_ to allow for these calls, patching _TerraConfig_ to remove the login requirement, or creating some kind of new application to help us administer the EVSE.

Our first step was to start pulling apart the Android app - the examples below use [APKLab](https://github.com/APKLab/APKLab) to quickly tear the APK apart.

It's a fairly simply written thing for what it is, and finding the function that dealt with configuring OCPP was quite straight forward. There's some UI activity code in `p006ui`, but what we're really interested in is `CDBleClient.ocppServerConfigure()`:

```java {filename="com/chargedot/bluetooth/library/CDBleClient.java"}
public void ocppServerConfigure(HashMap<String, String> hashMap, WriteListener writeListener) throws ParamIllegalException {
    // Loads of validation code lives here
    // ...
    writeAndResp(RequestBodyFactory.getInstance().ocppServerConfigure(hashMap));
}
```

`writeAndResp()` does some basic sanity checking, then calls this function in `BluetoothClient.java`:

```java {filename="com/chargedot/bluetooth/library/BluetoothClient.java"}
@Override // com.chargedot.bluetooth.library.common.IBluetoothClient
public void writeNoRsp(String str, UUID uuid, UUID uuid2, byte[] bArr, BleWriteResponse bleWriteResponse) {
    BluetoothLog.m651v(String.format("writeNoRsp %s: service = %s, character = %s, value = %s", str, uuid, uuid2, ByteUtils.byteToString(bArr)));
    this.mClient.writeNoRsp(str, uuid, uuid2, bArr, (BleWriteResponse) ProxyUtils.getUIProxy(bleWriteResponse));
}
```

and the `RequestBodyFactory`'s `ocppServerConfigure()` function is a lovely, easy-to-understand byte builder:

```java {filename="com/chargedot/bluetooth/library/RequestBodyFactory.java"}
public byte[] ocppServerConfigure(HashMap<String, String> hashMap) {
        ByteArrayOutputStream byteArrayOutputStream;
        try {
            int intValue = Integer.valueOf(hashMap.get("serverEnable")).intValue();
            String str = hashMap.get("domainUrl");
            int intValue2 = Integer.valueOf(hashMap.get("port")).intValue();
            int intValue3 = Integer.valueOf(hashMap.get("protocolType")).intValue();
            
            // .. etc

        } catch (Exception e) {
            e = e;
        }
        try {
            return wrap(CMD.REQUEST_OCPP_SERVER_CONFIGURE, byteArrayOutputStream.toByteArray());
        } catch (Exception e2) {
            e = e2;
            BluetoothLog.m653e(e);
            return null;
        }
    }
```

At this point, we knew we were dealing with something probably fairly straight forward to now pick apart - we're simply building byte arrays and throwing them out over a standard Bluetooth Low Energy connection. There are separate functions that deal with the responses, but it's easy to understand how these are dealt with from looking at the bluetooth library:

```java {filename="com/chargedot/bluetooth/library/response/OcppServerConfigureResponse.java"}
public class OcppServerConfigureResponse extends CDBleResponse {
    @Override // com.chargedot.bluetooth.library.response.CDBleResponse
    public void process(String str) {
        int i;
        if (!StringUtils.isBlank(str) && str.length() >= 32) {
            String substring = str.substring(2, 4);
            String substring2 = str.substring(32);
            if (substring2.length() < 2) {
                return;
            }
// .. etc
```

and the UI code:
```java
@Override // com.chargedot.bluetooth.library.listener.WriteListener
public void onReceive(OcppServerConfigureResponse ocppServerConfigureResponse) {
    // ...
    if (ocppServerConfigureResponse != null && ocppServerConfigureResponse.getCode() > 0) {
        int code = ocppServerConfigureResponse.getCode();
        boolean z = true;
        if (code != 100) {
            if (code == 101) {
                OCPPServerActivity.this.configurationFailed(1);
                return;
            } else if (code == 114) {
                OCPPServerActivity.this.configurationFailed(2);
                return;
            } else if (code != 115) {
                switch (code) {
                    case 109:
                        OCPPServerActivity.this.configureComplete();
                        return;
                    case 110:
                        OCPPServerActivity.this.configurationFailed(3);
                        return;
                    case 111:
                        OCPPServerActivity.this.isConfiguring = true;
                        return;
                    default:
                        return;
                }
            /// ... etc
    }
}
```

I make the decision at this point that the best course of action was to start building a new app that just lets us build these requests ourselves - we didn't know how integrated the installer login was into the app, and screwing around with that seemed overly complicated for what we wanted to achieve.

After taking a look at the _ChargerSync_ decompliation and realising it uses basically the exact same library, I made a packet dump of a session with the charger from an iPhone running the application using XCode's _PacketLogger_ (you can find a basic guide on it [here](https://mezdanak.de/2019/07/12/ios-bluetooth-packet-logging/)). This gives us the basic logic flow of a Bluetooth session:

```goat
┌────────────────────────────────────────┐     ┌────────────┐   ┌───────────┐     ┌──────────────┐   ┌───────────────┐     ┌──────────────────┐   ┌───────────────────┐  ┌────────────────────┐
│BTLE Connect                            ├────►│Authenticate├──►│Receive    ├────►│Request Status├──►│Status Response├────►│Request Capacities├──►│Capacities Response├─►│Session Continues...│
│(Service 0xFFF0, Maj 0xFFF4, Min 0xFFF3)│     └────────────┘   │Auth Token │     └──────────────┘   └───────────────┘     └──────────────────┘   └───────────────────┘  └────────────────────┘
└────────────────────────────────────────┘                      └───────────┘
```

Put another way (along with some information gleaned later on):
> 1. User selects "Connect" in Application
> 2. Application displays a list of chargers that can be connected to
> 3. Upon selecting a charger, Application prompts for PIN
> 4. Application verifies PIN with a request to ABB server _(spooky foreshadowing noises)_
> 5. If PIN is correct, Application opens a Bluetooth Low Energy session with the charger
> 6. Application authenticates itself with the charger using an encrypted Authorisation command
> 7. If authentication is successful, the charger responds with a token to be included with all future commands, and _audibly beeps twice_
> 8. The Application then proceeds with further commands to determine charger state, perform configuration tasks, etcetera


So I start looking in the most obvious place, the Authentication packet factory.

```java {filename="com/chargedot/bluetooth/library/RequestBodyFactory.java"}
public byte[] buildIdentityAuthenticationRequestBody(String str) {
    byte[] bArr = new byte[48];
    // getmUserId returns the UserID of the user currently logged in to TerraConfig / ChargerSync.
    // This is just an integer, presumably the server-side database auto_increment ID.
    String valueOf = String.valueOf(CDBleClient.getInstance().getmUserId());
    // str (the function parameter) is the serial number of the charger.
    ByteUtils.fillBytes(bArr, 0, str.replace("-", ""));
    ByteUtils.fillBytes(bArr, str.length(), 0, 20 - str.length());
    ByteUtils.fillBytes(bArr, 20, 2, 1);
    ByteUtils.fillBytes(bArr, 21, 1, 1);
    ByteUtils.fillBytes(bArr, 22, valueOf);
    ByteUtils.fillBytes(bArr, valueOf.length() + 22, 0, 15 - valueOf.length());
    ByteUtils.fillBytes(bArr, 37, 0, 8);
    ByteUtils.fillBytes(bArr, 45, 0, 3);
    BluetoothLog.m654e(ByteUtils.byteToString(bArr));
    byte[] bArr2 = new byte[8];
    ByteUtils.fillBytes(bArr2, 0, 117, 1);
    ByteUtils.fillBytes(bArr2, 1, 99, 1);
    ByteUtils.fillBytes(bArr2, 2, 115, 1);
    ByteUtils.fillBytes(bArr2, 3, 101, 1);
    ByteUtils.fillBytes(bArr2, 4, 114, 1);
    ByteUtils.fillBytes(bArr2, 5, 118, 1);
    ByteUtils.fillBytes(bArr2, 6, 101, 1);
    ByteUtils.fillBytes(bArr2, 7, 114, 1);
    // it's 202*, why are we still using DES3?
    byte[] encrypt = DES3Utils.encrypt(bArr, bArr2);
    if (encrypt != null) {
        byte[] bArr3 = new byte[130];
        ByteUtils.fillBytes(bArr3, 0, 128, 2);
        ByteUtils.fillBytes(bArr3, 2, 0, 128);
        System.arraycopy(encrypt, 0, bArr3, 2, encrypt.length);
        return wrap(254, bArr3);
    }
    return wrap(254, new byte[0]);
}
```

A lot of the fillBytes calls here are probably bad decompliation, so don't read too hard into that. I transliterated this to go as the following:


```go {filename="duckfullstop/bluetacc/pkg/terraformer/tacw_commands.go:167"}
rArr := make([]byte, 48)

// remove dashes from serial because they are shown in some literature
copy(rArr[0:], strings.Replace(wb.SerialNumber, "-", "", -1))

// everything from the end of the serial to byte 20 should be 0

// wonder if these packets set authorization level?
// on TerraConfig iOS packet dump: [00 02]
// on TerraConfig Android disassembly: [02 01]
rArr[20] = 2
rArr[21] = 1

// this can be literally anything you want
const terraUserID int = 1337

copy(rArr[22:], fmt.Sprint(terraUserID))

// everything from the end of the User ID to byte 48 should be 0

// this data now gets encrypted in an extraordinarily secure fashion
// the terraEncryptKey is defined statically in the manifest (not supplied here for legal reasons)
eData, err := tripledesECB.TripleEcbDesEncrypt(rArr, []byte(terraEncryptKey))

if err != nil {
    return nil, err
}

// some magic
pArr := make([]byte, 130)
pArr[0] = 128
pArr[1] = 128
copy(pArr[2:], eData)
```


### The Glaring Omission

Some of you will have noticed the issue with `buildIdentityAuthenticationRequestBody()` already. That's right: **the authentication procedure does not take the PIN, or any kind of secret credential.** The only function parameter is the serial number of the charger, which isn't a secret at all because _the charger helpfully gives that to you as its Bluetooth device name_ - and even if that weren't the case, the serial is on a sticker on the side of every Wallbox (and, on models with a screen, in the bottom left of the screen).

You can shove (almost) whatever you like in mUserId, and you'll be authenticated. As far as we can tell, the only thing mUserId is used for is local logging of which user performed commands, but this is of course completely useless if an attacker can just set it to whatever they feel like.

I wrote up a very quick sample app on my laptop to throw one of these auth packets at the charger, and we were both greeted with a _Beep! Beep!_ from the charger indicating that a device had connected. We were both absolutely astonished. At this point, we both took a very long beverage break and contemplated our lives. _How on earth was this overlooked? Is there something we're missing? Does the ABB server have some magic wand it waves to let the EVSE know it can connect?_ The only answers we had (and still have) are "we have no idea", "nope", and "impossible (but keep reading)".

So why the heck does the app need the valid PIN? Simple, really:

```java {filename="com/abb/nebula/http/Api.java"}
public interface Api {
    // ...
    @POST("api/v3/device/pincode/check")
    Observable<HttpResponse<PinCodeCheck>> devicePinCodeCheck(@Body LinkedHashMap<String, Object> linkedHashMap, @HeaderMap LinkedHashMap<String, String> linkedHashMap2);
};
```

```java {filename="com/abb/nebula/data/bean/PinCodeCheck.java"}
public final class PinCodeCheck {
    private final int flag;
    private final int verify;
    
    // ...

    public PinCodeCheck(int i, int i2) {
        this.verify = i;
        this.flag = i2;
    }

    public final int getFlag() {
        return this.flag;
    }

    public final int getVerify() {
        return this.verify;
    }
}
```

`FragmentHome.java` doesn't decompile all that well, but you can hopefully get the gist
```java {filename="com/abb/nebula/p006ui/fragment/FragmentHome.java"}
/* JADX INFO: Access modifiers changed from: private */
/* renamed from: subscribeVM$lambda-6  reason: not valid java name */
public static final void m1117subscribeVM$lambda6(FragmentHome this$0, HttpResponse httpResponse) {
    Intrinsics.checkNotNullParameter(this$0, "this$0");
    if (httpResponse == null) {
        return;
    }
    if (httpResponse.getCode() == this$0.getSUCCESS_CODE()) {
        // Server returned 200 - function now returns based on response content
        if (httpResponse.getData() == null) {
            // Request to server returned no data
            this$0.bleConnecting = false;
            this$0.updateBleConnectStatus(ConnectMode.BLE, false);
            String string = this$0.getResources().getString(C0896R.string.dialog_msg_pin_code_invalid);
            Intrinsics.checkNotNullExpressionValue(string, "resources.getString(R.st…log_msg_pin_code_invalid)");
            this$0.checkPinCodeFail(string);
            return;
        } else if (((PinCodeCheck) httpResponse.getData()).getVerify() == 0) {
            // Request to server succeded, but the code check failed
            this$0.bleConnecting = false;
            this$0.updateBleConnectStatus(ConnectMode.BLE, false);
            String string2 = this$0.getResources().getString(C0896R.string.dialog_msg_pin_code_invalid);
            Intrinsics.checkNotNullExpressionValue(string2, "resources.getString(R.st…log_msg_pin_code_invalid)");
            this$0.checkPinCodeFail(string2);
            return;
        } else {
            // Request succeeded
            // "isUkDevice" defines whether the device was intended for the UK market (where there are special required configuration flags defined in legislation)
            this$0.isUkDevice = ((PinCodeCheck) httpResponse.getData()).getFlag() == 1;
            // Open the BLE connection to the wallbox
            this$0.bleConnect();
            return;
        }
    }
    // If the request wasn't successful, this codepath now runs
    this$0.bleConnecting = false;
    this$0.updateBleConnectStatus(ConnectMode.BLE, false);
    if (!TextUtils.isEmpty(httpResponse.getMsg()) && httpResponse.getCode() != 5003) {
        this$0.checkPinCodeFail(httpResponse.getMsg());
        return;
    }
    String string3 = this$0.getResources().getString(C0896R.string.dialog_msg_pin_code_invalid);
    Intrinsics.checkNotNullExpressionValue(string3, "resources.getString(R.st…log_msg_pin_code_invalid)");
    this$0.checkPinCodeFail(string3);
}
```

(more in `com/abb/nebula/p006ui/activity/ble/BleBaseActivity.java`)

I'm sure some members of the audience are crying and also contemplating their lives right now, but to spell it out: **The app itself calls out to the ABB server to verify the PIN, then connects to the EVSE. The EVSE has nothing to do with authentication whatsoever.** Indeed, if you were to theoretically skip the PIN screen in the app, everything would proceed like normal. It's effectively completely pointless.

For those of you that are thinking "wait, does the ABB server magically bless the Wallbox directly over the internet with permission to connect or something?", remember that the Wallbox may have absolutely no way of communicating with the world during setup except via Bluetooth (for example, if it's going to be connected via wifi, or indeed not connected at all and just used as a dumb charger).

## Disclosure, and the Proof of Concept

Not long after myself and this old acquaintance discovered this, we had a huge falling out over an unrelated matter, and lost contact. I cannot talk in great detail about the circumstances due to legal issues, but there was a mutual decision that ended up with my taking full ownership of the vulnerability, and of reporting. My personal health (and life generally) also kinda fell apart simultaneously, but I pushed on as hard as life permitted me to.

_puck_ stepped in massively here when I was over at hers for a night, and helped me tidy up the proof of concept code - she has a far better grasp on decompiled Android than I do, and we managed to flesh out some bits and pieces (including a wider set of commands). Without her help, I probably would have massively stalled on stress, and this probably wouldn't have gotten out the door in anywhere near as complete a form as it is today. To this end, she is listed as a co-author, and deserves just as much credit.


## The Moral of the Story

Developers: **NEVER, EVER TRUST THE CLIENT.** The server should _ALWAYS_ check validity of requests itself. This is basic security 101, folks, come on.

___

## A Final Personal Note

This vulnerability has been sat on my desk as unfinished business for far too long, and it's extraordinarily liberating to finally have the opportunity to talk about it.

As previously mentioned, this wouldn't have been possible without [puck](https://puck.moe)'s assistance with dissecting and properly understanding some of the Android code paths. A huge thanks is due - and if you're crediting me with this vulnerability, you should give equal credit to her, too!

A massive shout-out to [Jonathan Gitlin](https://arstechnica.com/author/jonathan-m-gitlin/) at _Ars Technica_ - this would have been jammed for all eternity without you prodding the right people!

My thanks to Heather Flanagan at ABB E-Mobility for helping progress this, and Sajan at the ABB _CSIRT_ for running the disclosure.

To all those who have helped keep me vaguely sane (Alice, Allie, Amy, Jade, Kat, Maple, Q, and Sarah, to name [but a few](https://queer.af/@duck/109609332671682333)), thank you. 💙

Finally: my work on this, like most of my personal work from the last 3 years, is dedicated to [Gwen](https://twitter.com/hipsterfont), who we lost in 2020. I'm sure she would've gotten a kick out of this insanity. 💔