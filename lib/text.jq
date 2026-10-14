# Text from the audited Mac (app, certificate and launch item names…) can hold control characters a
# terminal would run, such as an escape sequence that erases a line. printable keeps the text and
# drops them: tabs and newlines become spaces, the other C0, DEL and C1 characters go.
def printable:
  explode
  | map(if . == 9 or . == 10 then 32 end | select(. >= 32 and (. < 127 or . > 159)))
  | implode;
