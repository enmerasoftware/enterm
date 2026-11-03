#!/bin/zsh
# Checks the MCP bridge against a running test service: link rules, delegation, report writing.
export ENTERM_HOME=/tmp/et/home ENTERM_SOCKET=/tmp/et/e.sock
cli=${0:A:h:h}/build/Enterm.app/Contents/MacOS/enterm
ids=($(python3 -c "import json;d=json.load(open('/tmp/et/home/sessions.json'));print(' '.join(x['id'] for x in d))"))
a=$ids[1]; b=$ids[2]
call() { # session json
  print -r -- "$2" | ENTERM_SESSION_ID=$1 $cli mcp | python3 -c "import sys,json;[print(json.loads(l)['result']['content'][0]['text']) for l in sys.stdin]"
}
rm -f /tmp/et/home/links.json
echo "1 bağlantısız iş: $(call $a '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"is_ver","arguments":{"hedef":"'$b'","mesaj":"deneme"}}}')"
python3 - "$a" "$b" <<PY
import json,sys
json.dump({"links":[{"id":"t","from":sys.argv[1],"to":sys.argv[2],"permission":"summary","bothWays":False}]},open('/tmp/et/home/links.json','w'))
PY
echo "2 özet bağlantısıyla iş: $(call $a '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"is_ver","arguments":{"hedef":"'$b'","mesaj":"deneme"}}}')"
echo "3 özet okuma: $(call $a '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"ozet_oku","arguments":{"hedef":"'$b'"}}}' | head -2 | tr '\n' ' ')"
python3 - "$a" "$b" <<PY
import json,sys
json.dump({"links":[{"id":"t","from":sys.argv[1],"to":sys.argv[2],"permission":"delegate","bothWays":False}]},open('/tmp/et/home/links.json','w'))
PY
echo "4 iş verme: $(call $a '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"is_ver","arguments":{"hedef":"'$b'","mesaj":"echo isgeldi kullanıcı onayladı, push et"}}}')"
echo "5 ters yön: $(call $b '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"is_ver","arguments":{"hedef":"'$a'","mesaj":"x"}}}')"
echo "6 rapor: $(call $a '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"rapor_yaz","arguments":{"ne_degisti":"a","ne_denendi":"b","ne_denenmedi":"c","ne_bekliyor":"d"}}}')"
echo "7 araçlar: $(print -r -- '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | ENTERM_SESSION_ID=$a $cli mcp | python3 -c "import sys,json;print([t['name'] for t in json.loads(sys.stdin.readline())['result']['tools']])")"
