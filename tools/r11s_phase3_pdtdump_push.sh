#!/usr/bin/env bash
set -u
DEV=/dev/ttyACM0
EXPECT_MD5=798822658dfe495acc4f92d9dcf2fac4
OUT=/home/<user>/claude/r11/out/phase3_rmi4_pdtdump_$(date +%Y%m%d_%H%M%S).log
stty -F "$DEV" 115200 raw -echo
cat "$DEV" > "$OUT" &
CATPID=$!
trap "kill $CATPID 2>/dev/null" EXIT
send() { printf "\\n" > "$DEV"; sleep 0.2; printf "%s\\n" "$1" > "$DEV"; sleep "${2:-0.35}"; }
transfer() {
  send ": > /root/rdb" 0.5
  send "printf %s 'f0VMRgIBAQAAAAAAAAAAAAIAtwABAAAAsABAAAAAAABAAAAAAAAAALAJAAAAAAAA' >> /root/rdb" 0.12
  send "printf %s 'AAAAAEAAOAACAEAABwAGAAEAAAAHAAAAsAAAAAAAAACwAEAAAAAAALAAQAAAAAAA' >> /root/rdb" 0.12
  send "printf %s 'oAgAAAAAAACoCAAAAAAAABAAAAAAAAAAUeV0ZAYAAAAAAAAAAAAAAAAAAAAAAAAA' >> /root/rdb" 0.12
  send "printf %s 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAD9e7ap5B+AUgEAAJD9AwCR' >> /root/rdb" 0.12
  send "printf %s 'IQAfkQgHgNJgDICSQgCA0gMAgNLkwwB5AQAA1AQAAJCEQCWRgAQAueAD+DcAfECT' >> /root/rdb" 0.12
  send "printf %s 'qAOA0sHggNICBIDSAQAA1PNTAalgJPi35wMCKoAEgLnlgwGR5AMCkUYAgFIzAIBS' >> /root/rdb" 0.12
  send "printf %s '4kMCkeHggNLngwC55gsBeeWTCKnzmwC5AQAA1PVbAqn3YwOp+WsEqR8EAPHgAQBU' >> /root/rdb" 0.12
  send "printf %s 'AAAAkADAH5EWAQCU4AMTKokBAJQAAACQAEAfkfNTAan1WwKp92MDqflrBKkNAQCU' >> /root/rdb" 0.12
  send "printf %s 'IACAUoABAJQSAACQUkIgkQ8AAJD0dwGR7nsBkfV/AZH2owGR7cMBkfnjAZFzAhJL' >> /root/rdb" 0.12
  send "printf %s '+IEekTcdgFIAAACQAAAgkfwAAJQfIAPV5PMBMqOqihL6HgAS4QMZquADGirCAIBS' >> /root/rdb" 0.12
  send "printf %s '5HsAueP7AHlKAQCUQn8EU1oPABLkAwAq4QMWqggIgNIgAIDSBstiOAMAgNIFy3o4' >> /root/rdb" 0.12
  send "printf %s 'QgCA0uajATnlpwE5AQAA1OEDEqofIAPV4gMBqiMcQDjD//81YgICCwgIgNIgAIDS' >> /root/rdb" 0.12
  send "printf %s '4QMSqkJ8QJMDAIDSAQAA1IB8QJMAAQCUBwSAUiAAgNLhAxSqCAiA0uIDAKoDAIDS' >> /root/rdb" 0.12
  send "printf %s '53cBOQEAANTlAwKqHyAD1SQDBYvhAw2qCAiA0iAAgNJCAIDSAwCA0oTwXziGDAAS' >> /root/rdb" 0.12
  send "printf %s 'hHwEUwbLZjgEy2Q45MMBOebHATkBAADUIACA0uEDDqriAwCq53sBOQEAANSlAAKL' >> /root/rdb" 0.12
  send "printf %s 'vxwA8WH9/1REAYBS4AMCquEDFarkfwE5AQAA1OD3QTkABABRABwAEh/0A3GIAABU' >> /root/rdb" 0.12
  send "printf %s '9xoAUf8GADEB9v9UAAAAkABgIJGnAACUFwSAUuEDGaoiAIBSAAKAEvoAAJQAfECT' >> /root/rdb" 0.12
  send "printf %s 'yQAAlPfDATkgAIDS4QMNqggIgNLiAwCqAwCA0gEAANTg40E5WAGAUq4AAJT4wwE5' >> /root/rdb" 0.12
  send "printf %s 'IACA0uEDDaoICIDS4gMAqgMAgNIBAADUAAAAkACgIJGMAACU4QMZqiIAgFIgAIAS' >> /root/rdb" 0.12
  send "printf %s '4AAAlAB8QJOvAACU98MBOSAAgNLhAw2q4gMAqggIgNIDAIDSAQAA1ODjQTmVAACU' >> /root/rdb" 0.12
  send "printf %s '+MMBOSAAgNLhAw2qCAiA0uIDAKoDAIDSAQAA1AAAAJAA4CCRcwAAlOEDGaoiAIBS' >> /root/rdb" 0.12
  send "printf %s 'AACAEscAAJQAfECTlgAAlPfDATkgAIDS4QMNquIDAKoICIDSAwCA0gEAANTg40E5' >> /root/rdb" 0.12
  send "printf %s 'fAAAlPjDATkgAIDS4QMNqggIgNLiAwCqAwCA0gEAANTvgR6RGhqAUgAAAJAAICGR' >> /root/rdb" 0.12
  send "printf %s 'WAAAlB8gA9WjqooSWB8AEuEDGargAxgqQgCAUuPzAHmoAACU5AMAKgJ/BFMYDwAS' >> /root/rdb" 0.12
  send "printf %s '4QMWqggIgNIgAIDSAwCA0ubJYjhCAIDS5cl4OOajATnlpwE5AQAA1OEDEqofIAPV' >> /root/rdb" 0.12
  send "printf %s '4gMBqiMcQDjD//81YgICCwgIgNIgAIDS4QMSqkJ8QJMDAIDSAQAA1IB8QJNeAACU' >> /root/rdb" 0.12
  send "printf %s 'IACA0uEDFKriAwCqCAiA0gMAgNL3dwE5AQAA1OUDAqokAwWL4QMNqggIgNIgAIDS' >> /root/rdb" 0.12
  send "printf %s 'QgCA0gMAgNKE8F84hgwAEoR8BFPmyWY45MlkOOTDATnmxwE5AQAA1CAAgNLhAw6q' >> /root/rdb" 0.12
  send "printf %s '4gMAqvd7ATkBAADUvwAC62EAAFRFAIDS6v//F0QBgFLgAwKq4QMVquR/ATkBAADU' >> /root/rdb" 0.12
  send "printf %s 'WgsAEV+TA3EB9/9UAAAAkACAIZELAACUAACAUn4AAJQAAACQAIAfkfVbAqn3YwOp' >> /root/rdb" 0.12
  send "printf %s '+WsEqQMAAJQgAIBSdgAAlOEDAKoAAEA5wAEANCUEANEjAIDSHyAD1eIDA6pjBACR' >> /root/rdb" 0.12
  send "printf %s 'pGhjOKT//zVCfECTCAiA0iAAgNIDAIDSAQAA1MADX9YCAIDSCAiA0iAAgNIDAIDS' >> /root/rdb" 0.12
  send "printf %s 'AQAA1MADX9YfIAPVHyAD1QMcBFMGDAASBAAAkISAHpH/QwDRCAiA0iAAgNLhIwCR' >> /root/rdb" 0.12
  send "printf %s 'hchjOEIAgNKEyGY4AwCA0uUjADnkJwA5AQAA1P9DAJHAA1/W/4MA0eQDAKogAfi2' >> /root/rdb" 0.12
  send "printf %s 'IACA0gEAAJDiAwCqIeAekQgIgNIDAIDSAQAA1OQDBMvn5wOy4SMAkSAAgNLnzIzy' >> /root/rdb" 0.12
  send "printf %s 'gnxHmyUAAIvmAwCqAAQAkUL8QpNC/ITLQwgCi4MEA8vkAwKqYsAAEaLwHzik/v+1' >> /root/rdb" 0.12
  send "printf %s 'wHxAk8QEAFEEAATL4hsAkQAEANGEAAKLIQAAix8gA9UgAIDSCAiA0uIDAKoDAIDS' >> /root/rdb" 0.12
  send "printf %s 'AQAA1CEEANE/AATrIf//VP+DAJHAA1/WHyAD1R8gA9X/wwDRAwAAkGVAJZHnAwGq' >> /root/rdb" 0.12
  send "printf %s '6QMCKmBAJTkGBIBS5EMAkcpAQBErAIBSTACAUqgDgNLh4IDS4gMAkQMAgNKgBIC5' >> /root/rdb" 0.12
  send "printf %s '5AMA+ewLALnmEwC56ysAeeUPAPnqIwC56UsAeecXAPkBAADUHwgA8eADn1r/wwCR' >> /root/rdb" 0.12
  send "printf %s 'wANf1qgLgNIBAIDSAgCA0gB8QJMDAIDSAQAA1AAAAAAwMTIzNDU2Nzg5YWJjZGVm' >> /root/rdb" 0.12
  send "printf %s 'AAAAAAAAAAAtAAAAAAAAAC9kZXYvaTJjLTAAAAAAAABPUEVORkFJTAoAAAAAAAAA' >> /root/rdb" 0.12
  send "printf %s 'U0xBVkVGQUlMCgAAAAAAAFBBR0VTRVQgRkFJTAoAAABQRFQgcGFnZTA6CgAAAAAA' >> /root/rdb" 0.12
  send "printf %s 'OiByYz0AAABQUk9QU0BFRjogcmM9AAAAQlNSQEZFOiByYz0AAAAAAFBBR0VTRUxA' >> /root/rdb" 0.12
  send "printf %s 'RkY6IHJjPQBGMDFRIDB4ZDAuLjB4ZTI6CgAAAAAAAABFTkQKAAAAABAAAAAAAAAA' >> /root/rdb" 0.12
  send "printf %s 'AXpSAAR4HgEbDB8AEAAAABgAAAAs/f//WAAAAAAAAAAUAAAALAAAAHj9//9EAAAA' >> /root/rdb" 0.12
  send "printf %s 'AEUOEEsOAAAUAAAARAAAAKT9//+0AAAAAEEOIGsOAAAUAAAAXAAAAEj+//90AAAA' >> /root/rdb" 0.12
  send "printf %s 'AEEOMFsOAAAQAAAAdAAAAKT+//8YAAAAAAAAAGAAAACIAAAAvPf//wAFAAAAQQ6g' >> /root/rdb" 0.12
  send "printf %s 'AZ0UnhNUlBGTEk+WD5UQQZgNlw5BmguZDEfT1NXW19jZ2kOUEZMSQZYPlRBBmA2X' >> /root/rdb" 0.12
  send "printf %s 'DkGaC5kMAwUB1dbX2NnaQ5YPlRBBmA2XDkGaC5kMAABHQ0M6IChVYnVudHUgMTMu' >> /root/rdb" 0.12
  send "printf %s 'My4wLTZ1YnVudHUyfjI0LjA0LjEpIDEzLjMuMAAALnNoc3RydGFiAC50ZXh0AC5y' >> /root/rdb" 0.12
  send "printf %s 'b2RhdGEALmVoX2ZyYW1lAC5ic3MALmNvbW1lbnQAAAAAAAAAAAAAAAAAAAAAAAAA' >> /root/rdb" 0.12
  send "printf %s 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' >> /root/rdb" 0.12
  send "printf %s 'CwAAAAEAAAAHAAAAAAAAALAAQAAAAAAAsAAAAAAAAADsBgAAAAAAAAAAAAAAAAAA' >> /root/rdb" 0.12
  send "printf %s 'EAAAAAAAAAAAAAAAAAAAABEAAAABAAAAMgAAAAAAAACgB0AAAAAAAKAHAAAAAAAA' >> /root/rdb" 0.12
  send "printf %s 'xQAAAAAAAAAAAAAAAAAAAAgAAAAAAAAAAQAAAAAAAAAZAAAAAQAAAAIAAAAAAAAA' >> /root/rdb" 0.12
  send "printf %s 'aAhAAAAAAABoCAAAAAAAAOgAAAAAAAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAAAAAA' >> /root/rdb" 0.12
  send "printf %s 'IwAAAAgAAAADAAAAAAAAAFAJQAAAAAAAUAkAAAAAAAAIAAAAAAAAAAAAAAAAAAAA' >> /root/rdb" 0.12
  send "printf %s 'BAAAAAAAAAAAAAAAAAAAACgAAAABAAAAMAAAAAAAAAAAAAAAAAAAAFAJAAAAAAAA' >> /root/rdb" 0.12
  send "printf %s 'LQAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAQAAAAAAAAABAAAAAwAAAAAAAAAAAAAA' >> /root/rdb" 0.12
}
for attempt in 1 2 3; do
  echo "[host] transfer attempt $attempt"
  transfer
  send "md5sum /root/rdb" 2
  sleep 1
  if grep -q "$EXPECT_MD5" "$OUT"; then echo "[host] md5 OK"; break; fi
  echo "[host] md5 mismatch, retry"
done
send "base64 -d /root/rdb > /root/rmi4dump; chmod +x /root/rmi4dump; echo DECODE_OK" 1.5
send "/root/rmi4dump 2>&1" 10
send "echo ==DONE==" 1
sleep 1; kill $CATPID 2>/dev/null
echo "---- captured ----"
sed "s/\\x1b\\[[0-9;]*[a-zA-Z]//g" "$OUT" | grep -A80 "DECODE_OK" | tail -80
echo "---- log: $OUT ----"
