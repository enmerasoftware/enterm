#!/usr/bin/env python3
"""Lists the on-screen text of the Mac app that Resources/en.json has no English for.

The app is written in Turkish; English is a table keyed by the Turkish text. Built text ("Ekip \\(ad)")
is keyed with %@ in place of the parts. A string that is not on-screen text (a command, an identifier)
can be listed too: add it with itself as the value and it is not listed again.

Usage: scripts/strings.py            missing strings, one per line
       scripts/strings.py --json     the same as a JSON object ready to fill in
"""
import re, sys, json, glob, os
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
files=sorted(sum((glob.glob(root+'/'+pattern) for pattern in [
    'Sources/EntermApp/*.swift', 'Sources/EntermCore/*.swift', 'Sources/entermd/PhoneCenter.swift', 'Sources/enterm/MCPServer.swift',
    'enterm-ios/Enterm/*.swift', 'enterm-ios/EntermNotify/*.swift', 'enterm-ios/EntermWidgets/*.swift', 'enterm-ios/Shared/*.swift']), []))
TR=set('çğıöşüÇĞİÖŞÜ')
def literals(src):
    i=0;n=len(src)
    while i<n:
        c=src[i]
        if src.startswith('//',i) and not src.startswith('///',i) or src.startswith('///',i):
            j=src.find('\n',i); i=n if j<0 else j; continue
        if src.startswith('/*',i):
            j=src.find('*/',i); i=n if j<0 else j+2; continue
        if src.startswith('"""',i):
            j=src.find('"""',i+3); i=n if j<0 else j+3; continue
        if c=='#' and src.startswith('#"',i):
            j=src.find('"#',i+2); i=n if j<0 else j+2; continue
        if c=='"':
            j=i+1; out=[]; depth=0
            while j<n:
                ch=src[j]
                if ch=='\\' and j+1<n and src[j+1]=='(':
                    # interpolation
                    k=j+2; d=1
                    while k<n and d:
                        if src[k]=='(': d+=1
                        elif src[k]==')': d-=1
                        elif src[k]=='"':
                            k2=k+1
                            while k2<n and src[k2]!='"':
                                if src[k2]=='\\': k2+=1
                                k2+=1
                            k=k2
                        k+=1
                    out.append('\x00'); j=k; continue
                if ch=='\\': out.append(src[j:j+2]); j+=2; continue
                if ch=='"' or ch=='\n': break
                out.append(ch); j+=1
            raw=''.join(out)
            raw=re.sub(r'\\u\{([0-9A-Fa-f]+)\}',lambda m:chr(int(m.group(1),16)),raw)
            raw=raw.replace('\\\\','\x01').replace('\\"','"').replace("\\'","'").replace('\\n','\n').replace('\\t','\t').replace('\\r','\r').replace('\\0','').replace('\x01','\\')
            if '\x00' in raw: raw=raw.replace('%','%%').replace('\x00','%@')
            yield raw
            i=j+1; continue
        i+=1

def main():
    found = {}
    for f in files:
        for s in literals(open(f).read()):
            if not re.search(r'[A-Za-zÇĞİÖŞÜçğıöşü]', s) or s.replace('%@', '').strip() == '':
                continue
            if not any(ch in TR for ch in s):
                if re.fullmatch(r'[a-z][A-Za-z0-9_]*', s): continue
                if re.search(r'[./_:]', s) and ' ' not in s: continue
                if s.startswith(('http', '~', '/', '-', '#', '$', '{', '<', '.', 'com.', 'tr.')): continue
                if ' ' not in s and not re.match(r'[A-ZÇĞİÖŞÜ][a-zçğıöşü]+$', s): continue
            found.setdefault(s, os.path.relpath(f, root))
    table = json.load(open(os.path.join(root, 'Resources/en.json')))
    known = json.load(open(os.path.join(root, 'Resources/en-same.json'))) if os.path.exists(os.path.join(root, 'Resources/en-same.json')) else []
    missing = {k: v for k, v in found.items() if k not in table and k not in known}
    if '--json' in sys.argv:
        print(json.dumps({k: '' for k in missing}, ensure_ascii=False, indent=1))
    else:
        for k, v in missing.items(): print(f'{v}: {k}')
    sys.exit(1 if missing and '--check' in sys.argv else 0)

main()
