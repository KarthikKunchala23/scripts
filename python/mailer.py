#!/usr/bin/env python3
"""
mailer.py
Simple SMTP mail sender used by the bash alert script.
Usage:
  mailer.py --to recipient@example.com --subject "SUB" --body-file /tmp/mail_body
Environment variables (recommended):
  SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS, SMTP_FROM, SMTP_STARTTLS (true/false)
"""
import os, sys, argparse, smtplib, ssl
from email.message import EmailMessage

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--to', required=True)
    p.add_argument('--subject', required=True)
    p.add_argument('--body-file', required=True)
    args = p.parse_args()

    smtp_host = os.environ.get('SMTP_HOST', 'smtp.gmail.com')
    smtp_port = int(os.environ.get('SMTP_PORT', '587'))
    smtp_user = os.environ.get('SMTP_USER', '')
    smtp_pass = os.environ.get('SMTP_PASS', '')
    smtp_from = os.environ.get('SMTP_FROM', smtp_user or 'monitor@example.com')
    starttls = os.environ.get('SMTP_STARTTLS', 'true').lower() in ('1','true','yes')

    # read body
    try:
        with open(args.body_file, 'r') as f:
            body = f.read()
    except Exception as e:
        print("Error reading body file:", e, file=sys.stderr)
        return 3

    msg = EmailMessage()
    msg['From'] = smtp_from
    msg['To'] = args.to
    msg['Subject'] = args.subject
    msg.set_content(body)

    try:
        if starttls:
            context = ssl.create_default_context()
            with smtplib.SMTP(smtp_host, smtp_port, timeout=30) as server:
                server.ehlo()
                server.starttls(context=context)
                server.ehlo()
                if smtp_user:
                    server.login(smtp_user, smtp_pass)
                server.send_message(msg)
        else:
            with smtplib.SMTP_SSL(smtp_host, smtp_port, timeout=30) as server:
                if smtp_user:
                    server.login(smtp_user, smtp_pass)
                server.send_message(msg)
    except Exception as e:
        print("SMTP send failed:", e, file=sys.stderr)
        return 4

    return 0

if __name__ == '__main__':
    sys.exit(main())
