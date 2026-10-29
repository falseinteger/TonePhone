#!/usr/bin/env python3
"""
Minimal SIP server for testing TonePhone locally. Development only.

Acts as registrar and call peer on one UDP port, so the app can be exercised
without a real provider: registration with digest authentication, incoming
calls, outgoing calls (answered automatically), hold, hang-up, and
voicemail notifications (message-summary).

Usage:
    scripts/dev-sip-server.py [--bind IP] [--port 5070] [--user alice] [--password secret]

It listens on this Mac's LAN address by default (baresip does not place
calls to loopback addresses) and prints it. Configure an account in
TonePhone with that address as the server, port 5070, UDP, and the same
username and password.

Type commands on stdin while it runs:
    call [number] [name]   ring the registered client (default +14155550123 "Alice Johnson")
    cancel                 caller hangs up before answer (missed call)
    bye                    hang up the current call
    voicemail N            report N new voicemail messages (0 clears)
    status                 show registration and calls
    quit

Outgoing calls from the app are answered after 2 seconds. Dial a number
starting with 486 to get Busy, 404 to get Not Found.

Calls that offer SDES encryption (a=crypto) are answered with a key, so the
app shows them as encrypted.

Not a real SIP implementation: no retransmissions, no media (RTP).
"""

import argparse
import base64
import hashlib
import random
import re
import socket
import string
import sys
import threading
import time

REALM = "tonephone.test"


def rand(n=10):
    return "".join(random.choices(string.ascii_lowercase + string.digits, k=n))


def md5(text):
    return hashlib.md5(text.encode()).hexdigest()


def parse(data):
    text = data.decode(errors="replace")
    head, _, body = text.partition("\r\n\r\n")
    lines = head.split("\r\n")
    start = lines[0]
    headers = []
    for line in lines[1:]:
        if ":" in line:
            name, value = line.split(":", 1)
            headers.append((name.strip(), value.strip()))
    return start, headers, body


def header(headers, name):
    for key, value in headers:
        if key.lower() == name.lower():
            return value
    return None


def all_headers(headers, name):
    return [v for k, v in headers if k.lower() == name.lower()]


def sdp(host, port=40000, offer=""):
    """SDP answer (or offer when `offer` is empty).

    When the offer asks for SDES encryption (a=crypto), the answer accepts
    the first suite with a random key, so the app reports the call as
    encrypted. Offers carry a key too, so calls placed from here are
    encrypted when the account allows it. No RTP is sent either way.
    """
    proto = "RTP/SAVP" if "RTP/SAVP" in offer else "RTP/AVP"
    crypto = ""
    suite = re.search(r"a=crypto:(\d+) (\S+) ", offer)
    if suite or not offer:
        tag, name = (suite.group(1), suite.group(2)) if suite else ("1", "AES_CM_128_HMAC_SHA1_80")
        key = base64.b64encode(random.randbytes(30)).decode()
        crypto = f"a=crypto:{tag} {name} inline:{key}\r\n"
    # baresip ignores loopback addresses, so advertise the LAN address
    return (
        "v=0\r\n"
        f"o=- 1 1 IN IP4 {host}\r\n"
        "s=-\r\n"
        f"c=IN IP4 {host}\r\n"
        "t=0 0\r\n"
        f"m=audio {port} {proto} 0 101\r\n"
        "a=rtpmap:0 PCMU/8000\r\n"
        "a=rtpmap:101 telephone-event/8000\r\n"
        "a=sendrecv\r\n"
        + crypto
    )


class Server:
    def __init__(self, bind, port, user, password):
        self.port = port
        self.user = user
        self.password = password
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind((bind, port))
        self.host = bind
        self.nonce = rand(16)
        self.client = None          # (ip, port) of the registered client
        self.client_uri = None
        self.call = None            # dialog of the server-initiated call
        self.pending = {}           # Call-ID -> (headers, addr, tag) of unanswered INVITEs
        self.mwi = None             # voicemail subscription dialog
        self.new_messages = 0
        self.lock = threading.Lock()

    def log(self, text):
        print(f"[sip] {text}", flush=True)

    def send(self, text, addr):
        self.sock.sendto(text.encode(), addr)

    def respond(self, headers, addr, code, reason, extra=None, body="", to_tag=None):
        lines = [f"SIP/2.0 {code} {reason}"]
        for via in all_headers(headers, "Via"):
            if ";rport" in via and "rport=" not in via:
                via = via.replace(";rport", f";rport={addr[1]};received={addr[0]}", 1)
            lines.append(f"Via: {via}")
        lines.append(f"From: {header(headers, 'From')}")
        to = header(headers, "To")
        if to_tag and ";tag=" not in to:
            to += f";tag={to_tag}"
        lines.append(f"To: {to}")
        lines.append(f"Call-ID: {header(headers, 'Call-ID')}")
        lines.append(f"CSeq: {header(headers, 'CSeq')}")
        for item in extra or []:
            lines.append(item)
        if body:
            lines.append("Content-Type: application/sdp")
        lines.append("Server: TonePhone dev SIP server")
        lines.append(f"Content-Length: {len(body.encode())}")
        self.send("\r\n".join(lines) + "\r\n\r\n" + body, addr)

    # MARK: Requests from the client

    def check_auth(self, method, headers):
        auth = header(headers, "Authorization") or header(headers, "Proxy-Authorization")
        if not auth:
            return False
        params = dict(re.findall(r'(\w+)="?([^",]*)"?', auth))
        ha1 = md5(f"{params.get('username')}:{REALM}:{self.password}")
        ha2 = md5(f"{method}:{params.get('uri')}")
        if "qop" in params:
            expected = md5(f"{ha1}:{params.get('nonce')}:{params.get('nc')}:{params.get('cnonce')}:{params.get('qop')}:{ha2}")
        else:
            expected = md5(f"{ha1}:{params.get('nonce')}:{ha2}")
        ok = params.get("username") == self.user and params.get("response") == expected
        if not ok:
            self.log(f"authentication failed for user {params.get('username')!r}")
        return ok

    def on_register(self, headers, addr):
        if not self.check_auth("REGISTER", headers):
            self.respond(headers, addr, 401, "Unauthorized",
                         [f'WWW-Authenticate: Digest realm="{REALM}", nonce="{self.nonce}", algorithm=MD5'])
            return
        contact = header(headers, "Contact") or ""
        expires = header(headers, "Expires")
        match = re.search(r"expires=(\d+)", contact)
        if match:
            expires = match.group(1)
        expires = int(expires or 3600)
        with self.lock:
            if expires == 0:
                self.client = None
                self.log("client unregistered")
            else:
                self.client = addr
                uri = re.search(r"<([^>]+)>", contact)
                self.client_uri = uri.group(1) if uri else f"sip:{self.user}@{addr[0]}:{addr[1]}"
                self.log(f"registered {self.client_uri} from {addr[0]}:{addr[1]} for {expires}s")
        self.respond(headers, addr, 200, "OK", [f"Contact: {contact}", f"Expires: {expires}"])

    def on_invite(self, headers, body, addr):
        to = header(headers, "To") or ""
        number = re.search(r"sip:([^@>;]+)", to)
        number = number.group(1) if number else "?"
        tag = rand()
        self.log(f"outgoing call to {number}")
        self.respond(headers, addr, 100, "Trying")
        if number.startswith("486"):
            self.respond(headers, addr, 486, "Busy Here", to_tag=tag)
            return
        if number.startswith("404"):
            self.respond(headers, addr, 404, "Not Found", to_tag=tag)
            return
        self.respond(headers, addr, 180, "Ringing", to_tag=tag)
        call_id = header(headers, "Call-ID")
        self.pending[call_id] = (headers, addr, tag)

        def answer():
            time.sleep(2)
            if self.pending.pop(call_id, None) is None:
                return  # cancelled while ringing
            self.respond(headers, addr, 200, "OK",
                         [f"Contact: <sip:{number}@{self.host}:{self.port}>"],
                         body=sdp(self.host, 40002, body), to_tag=tag)
            self.log(f"answered call to {number}")
        threading.Thread(target=answer, daemon=True).start()

    # MARK: Voicemail (RFC 3842)

    def on_subscribe(self, headers, addr):
        if (header(headers, "Event") or "").split(";")[0].strip() != "message-summary":
            self.respond(headers, addr, 489, "Bad Event")
            return
        expires = int(header(headers, "Expires") or 3600)
        to_tag = re.search(r"tag=([^;]+)", header(headers, "To") or "")
        to_tag = to_tag.group(1) if to_tag else rand()
        contact = re.search(r"<([^>]+)>", header(headers, "Contact") or "")
        self.respond(headers, addr, 200, "OK",
                     [f"Contact: <sip:voicemail@{self.host}:{self.port}>", f"Expires: {expires}"],
                     to_tag=to_tag)
        if expires == 0:
            self.mwi = None
            self.log("voicemail subscription ended")
            return
        if not self.mwi or self.mwi["call_id"] != header(headers, "Call-ID"):
            self.mwi = {"cseq": 0}
        self.mwi.update({
            "call_id": header(headers, "Call-ID"), "addr": addr,
            "uri": contact.group(1) if contact else self.client_uri,
            "local": header(headers, "To").split(";tag=")[0] + f";tag={to_tag}",
            "remote": header(headers, "From"), "expires": expires,
        })
        self.log("client subscribed to voicemail")
        self.notify_voicemail()

    def notify_voicemail(self, count=None):
        if count is not None:
            self.new_messages = count
        m = self.mwi
        if not m:
            self.log("no voicemail subscription; enable “Show new voicemail” for the account")
            return
        m["cseq"] += 1
        body = (f"Messages-Waiting: {'yes' if self.new_messages else 'no'}\r\n"
                f"Message-Account: sip:voicemail@{REALM}\r\n"
                f"Voice-Message: {self.new_messages}/0 (0/0)\r\n")
        lines = [
            f"NOTIFY {m['uri']} SIP/2.0",
            f"Via: SIP/2.0/UDP {self.host}:{self.port};branch=z9hG4bK{rand()};rport",
            "Max-Forwards: 70",
            f"From: {m['local']}",
            f"To: {m['remote']}",
            f"Call-ID: {m['call_id']}",
            f"CSeq: {m['cseq']} NOTIFY",
            f"Contact: <sip:voicemail@{self.host}:{self.port}>",
            "Event: message-summary",
            f"Subscription-State: active;expires={m['expires']}",
            "Content-Type: application/simple-message-summary",
            f"Content-Length: {len(body.encode())}",
        ]
        self.send("\r\n".join(lines) + "\r\n\r\n" + body, m["addr"])
        self.log(f"sent voicemail status: {self.new_messages} new")

    # MARK: Calls to the client

    def place_call(self, number, name):
        with self.lock:
            if not self.client:
                self.log("no client registered")
                return
            target, uri = self.client, self.client_uri
        call_id = f"{rand()}@{REALM}"
        self.call = {
            "call_id": call_id, "from_tag": rand(), "to_tag": None,
            "addr": target, "uri": uri, "number": number, "name": name,
            "branch": "z9hG4bK" + rand(), "cseq": 1, "answered": False,
        }
        self.send_request("INVITE", body=sdp(self.host, 40000))
        self.log(f"ringing client: {name} <{number}>")

    def send_request(self, method, body="", branch=None, cseq=None):
        c = self.call
        if not c:
            return
        if cseq is None:
            c["cseq"] += 0 if method in ("INVITE", "ACK", "CANCEL") else 1
            cseq = c["cseq"]
        to = f"<{c['uri']}>" + (f";tag={c['to_tag']}" if c["to_tag"] and method != "CANCEL" else "")
        lines = [
            f"{method} {c['uri']} SIP/2.0",
            f"Via: SIP/2.0/UDP {self.host}:{self.port};branch={branch or ('z9hG4bK' + rand())};rport",
            "Max-Forwards: 70",
            f"From: \"{c['name']}\" <sip:{c['number']}@{REALM}>;tag={c['from_tag']}",
            f"To: {to}",
            f"Call-ID: {c['call_id']}",
            f"CSeq: {cseq} {method}",
            f"Contact: <sip:{c['number']}@{self.host}:{self.port}>",
        ]
        if body:
            lines.append("Content-Type: application/sdp")
        lines.append(f"Content-Length: {len(body.encode())}")
        if method in ("INVITE", "CANCEL"):
            lines[1] = f"Via: SIP/2.0/UDP {self.host}:{self.port};branch={c['branch']};rport"
        self.send("\r\n".join(lines) + "\r\n\r\n" + body, c["addr"])

    def on_response(self, start, headers, addr):
        code = int(start.split()[1])
        cseq = header(headers, "CSeq") or ""
        c = self.call
        if not c or header(headers, "Call-ID") != c["call_id"]:
            return
        if "INVITE" in cseq:
            to = header(headers, "To") or ""
            tag = re.search(r"tag=([^;]+)", to)
            if tag:
                c["to_tag"] = tag.group(1)
            if code == 180:
                self.log("client is ringing")
            elif code == 200:
                c["answered"] = True
                self.send_request("ACK", cseq=1)
                self.log("client answered")
            elif code >= 300:
                self.send_request("ACK", cseq=1, branch=c["branch"])
                self.log(f"client rejected the call: {start}")
                self.call = None
        elif "BYE" in cseq or "CANCEL" in cseq:
            self.log(f"{cseq.split()[-1]} acknowledged: {code}")

    def cancel(self):
        if not self.call or self.call["answered"]:
            self.log("no ringing call to cancel")
            return
        self.send_request("CANCEL", cseq=1)
        self.log("caller cancelled")

    def bye(self):
        if not self.call or not self.call["answered"]:
            self.log("no connected server call; hang up from the app instead")
            return
        self.send_request("BYE")
        self.call = None
        self.log("hung up")

    # MARK: Main loop

    def serve(self):
        self.log(f"listening on udp {self.host}:{self.port} (user {self.user!r}, realm {REALM})")
        while True:
            data, addr = self.sock.recvfrom(65535)
            if data.strip() in (b"", b"\r\n\r\n"):
                continue  # keep-alive
            try:
                start, headers, body = parse(data)
            except Exception as error:  # noqa: BLE001
                self.log(f"unparsable packet: {error}")
                continue
            if start.startswith("SIP/2.0"):
                self.on_response(start, headers, addr)
                continue
            method = start.split()[0]
            if method == "REGISTER":
                self.on_register(headers, addr)
            elif method == "INVITE":
                if self.call and header(headers, "Call-ID") == self.call["call_id"]:
                    # re-INVITE (hold/resume) on the server-initiated call
                    self.respond(headers, addr, 200, "OK",
                                 [f"Contact: <sip:x@{self.host}:{self.port}>"], body=sdp(self.host, 40000, body))
                elif "tag=" in (header(headers, "To") or ""):
                    self.respond(headers, addr, 200, "OK",
                                 [f"Contact: <sip:x@{self.host}:{self.port}>"], body=sdp(self.host, 40002, body))
                else:
                    self.on_invite(headers, body, addr)
            elif method in ("BYE", "CANCEL"):
                self.respond(headers, addr, 200, "OK")
                invite = self.pending.pop(header(headers, "Call-ID"), None) if method == "CANCEL" else None
                if invite:
                    self.respond(invite[0], invite[1], 487, "Request Terminated", to_tag=invite[2])
                if self.call and header(headers, "Call-ID") == self.call["call_id"]:
                    self.call = None
                self.log(f"client sent {method}")
            elif method == "ACK":
                pass
            elif method == "SUBSCRIBE":
                self.on_subscribe(headers, addr)
            elif method in ("OPTIONS", "INFO", "NOTIFY", "PUBLISH"):
                self.respond(headers, addr, 200, "OK")
                if method == "INFO":
                    self.log("received keypad tone (SIP INFO)")
            else:
                self.respond(headers, addr, 501, "Not Implemented")


def lan_address():
    """The address used for outgoing traffic, without sending anything."""
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect(("192.0.2.1", 9))
        return probe.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        probe.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--bind", default=lan_address(), help="address to listen on (default: LAN address)")
    parser.add_argument("--port", type=int, default=5070)
    parser.add_argument("--user", default="alice")
    parser.add_argument("--password", default="secret")
    args = parser.parse_args()

    server = Server(args.bind, args.port, args.user, args.password)
    threading.Thread(target=server.serve, daemon=True).start()

    for line in sys.stdin:
        parts = line.strip().split(maxsplit=2)
        if not parts:
            continue
        command = parts[0]
        if command == "call":
            number = parts[1] if len(parts) > 1 else "+14155550123"
            name = parts[2].strip("\"") if len(parts) > 2 else "Alice Johnson"
            server.place_call(number, name)
        elif command == "cancel":
            server.cancel()
        elif command == "bye":
            server.bye()
        elif command == "voicemail":
            try:
                server.notify_voicemail(int(parts[1]) if len(parts) > 1 else 1)
            except ValueError:
                server.log("usage: voicemail N")
        elif command == "status":
            server.log(f"client: {server.client_uri or 'none'}, call: {server.call['number'] if server.call else 'none'}")
        elif command == "quit":
            break
        else:
            server.log("commands: call [number] [name] | cancel | bye | voicemail N | status | quit")


if __name__ == "__main__":
    main()
