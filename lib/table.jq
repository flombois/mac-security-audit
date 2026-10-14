# Table rendering, adapted from github-scripts' lib/table.jq; expects $isTerminal, $useColor and
# $terminalWidth. A cell is an array of {text, style} segments, where a style is an ANSI SGR code.

def bold: "1";
def dim: "2";
def red: "31";
def green: "32";
def yellow: "33";
def blue: "34";
def magenta: "35";

# Display width: wide (CJK, emoji) characters take two columns, combining marks none.
def wideRanges:
  [[4352,4447],[8986,8987],[9193,9196],[9200,9203],[9725,9726],[9748,9749],[9800,9811],[9855,9855],
   [9875,9875],[9889,9889],[9898,9899],[9917,9918],[9924,9925],[9934,9934],[9940,9940],[9962,9962],
   [9970,9971],[9973,9973],[9978,9978],[9981,9981],[9989,9989],[9994,9995],[10024,10024],[10060,10060],
   [10062,10062],[10067,10069],[10071,10071],[10133,10135],[10160,10160],[10175,10175],[11035,11036],
   [11088,11088],[11093,11093],[11904,12350],[12353,42191],[44032,55203],[63744,64255],[65072,65103],
   [65280,65376],[65504,65510],[127744,128591],[128640,128767],[129280,129535],[129648,129791],
   [131072,262141]];

def charWidth:
  . as $code
  | if $code < 32 or ($code >= 768 and $code <= 879) or ($code >= 8203 and $code <= 8207)
       or ($code >= 65024 and $code <= 65039) or ($code >= 127995 and $code <= 127999) then 0
    elif $code < 4352 or ($code >= 9204 and $code < 9725) then 1
    elif any(wideRanges[]; $code >= .[0] and $code <= .[1]) then 2
    else 1 end;

def textWidth: if utf8bytelength == length then length else explode | map(charWidth) | add // 0 end;

# The width of a rendered line, past its colour codes.
def visibleWidth: gsub("\u001b\\[[0-9;]*m"; "") | textWidth;

# The longest start of the text that fits $room columns.
def clipText($room):
  reduce explode[] as $code ({codes: [], room: $room};
    if .room < 0 then .
    else ($code | charWidth) as $width
      | if $width <= .room then .codes += [$code] | .room -= $width else .room = -1 end
    end)
  | .codes | implode;

def times($count): if $count > 0 then . * $count else "" end;
def paint($style):
  if $useColor and $style != "" and . != "" then "\u001b[\($style)m\(.)\u001b[0m" else . end;

def cell($style): [{text: ., style: $style}];
def cellWidth: map(.text | textWidth) | add // 0;
def renderInline: map(.style as $style | .text | paint($style)) | join("");

# Packs cells into as few lines as fit $width, joined by $separator.
def wrapCells($width; $separator):
  reduce .[] as $cell ([];
    if . == [] then [$cell]
    elif (.[-1] + $separator + $cell | cellWidth) <= $width then .[-1] += $separator + $cell
    else . + [$cell] end);

def clipCell($width):
  if cellWidth <= $width then .
  else
    reduce .[] as $segment ({room: ($width - 1), kept: []};
      .room as $room
      | if $room > 0
        then .kept += [$segment | .text |= clipText($room)] | .room -= ($segment.text | textWidth)
        else . end)
    | .kept + ("…" | cell(""))
  end;

def renderCell($width; $align):
  clipCell($width) as $cell
  | (" " | times($width - ($cell | cellWidth))) as $padding
  | if $align == "right" then $padding + ($cell | renderInline) else ($cell | renderInline) + $padding end;

# A footer entry such as "3 fail", left out when the count is zero.
def tally($label; $style): if . > 0 then "\(.) \($label)" | cell($style) else empty end;

# Rounded frames for the terminal, $width columns wide; the labels and lines are rendered strings.
# The right label is left out when both don't fit.
def frameTop($left; $right; $width):
  def padded: if . == "" then "" else " \(.) " end;
  ($left | padded) as $leftLabel
  | ($width - 4 - ($leftLabel | visibleWidth)) as $room
  | ($right | padded | if visibleWidth < $room then . else "" end) as $rightLabel
  | ($room - ($rightLabel | visibleWidth)) as $fill
  | ("╭─" | paint(dim)) + $leftLabel + ("─" | times($fill) | paint(dim)) + $rightLabel + ("─╮" | paint(dim));

# A line too wide for the frame goes without its right border. frameRow takes the line's width.
def frameRow($used; $width):
  ($width - 4 - $used) as $gap
  | ("│ " | paint(dim)) + .
    + (if $gap < 0 then "" else (" " | times($gap)) + (" │" | paint(dim)) end);

def frameLine($width): frameRow(visibleWidth; $width);

def frameDivider($width): "├" + ("─" | times($width - 2)) + "┤" | paint(dim);
def frameBottom($width): "╰" + ("─" | times($width - 2)) + "╯" | paint(dim);

# Column widths in $width columns: the flex column takes what the others leave, max columns grow to
# their full width when there is room, and shrink, widest first and down to 12, to give the flex
# column up to 40.
def columnWidths($rows; $width):
  . as $columns
  | length as $count
  | [$columns[] | .key as $key | [(.header | textWidth), ($rows[] | .[$key] // [] | cellWidth)] | max] as $full
  | [range(0; $count) | [$full[.], ($columns[.].max // infinite)] | min] as $capped
  | [range(0; $count) | select($columns[.].flex)][0] as $flex
  | [range(0; $count) | select(. != $flex)] as $fixed
  | ($width - (2 * $count - 1)) as $room
  | ($room - ([$fixed[] | $capped[.]] | add // 0) - $full[$flex]) as $spare
  | (reduce $fixed[] as $index ({widths: $capped, spare: $spare};
       ([$full[$index] - .widths[$index], .spare] | min) as $extra
       | if $extra > 0 then .widths[$index] += $extra | .spare -= $extra else . end)
     | .widths) as $grown
  | ([$full[$flex], 20] | min) as $flexMinimum
  | ([$full[$flex], 40] | min) as $flexTarget
  | [$fixed[] | select($columns[.].max)] as $squeezable
  | ({widths: $grown, short: ($flexTarget - $room + ([$fixed[] | $grown[.]] | add // 0))}
     | until(.short <= 0 or ([$squeezable[] as $index | .widths[$index]] | max // 0) <= 12;
         .widths as $widths
         | ($squeezable | max_by($widths[.])) as $widest
         | .widths[$widest] -= 1 | .short -= 1)
     | .widths) as $squeezed
  | ($room - ([$fixed[] | $squeezed[.]] | add // 0)) as $flexRoom
  | $squeezed
  | .[$flex] = ([if $isTerminal then $flexRoom else [$flexRoom, $full[$flex]] | min end, $flexMinimum] | max);

def tableWidth: add + 2 * (length - 1);

# Leaves out the drop columns, last first, while the table is wider than $width.
def fitColumns($rows; $width):
  columnWidths($rows; $width) as $widths
  | [range(0; length) as $index | select(.[$index].drop) | $index] as $droppable
  | if $isTerminal and ($widths | tableWidth) > $width - 1 and $droppable != []
    then del(.[$droppable[-1]]) | fitColumns($rows; $width)
    else {columns: ., widths: $widths} end;

# Renders {title, subtitle, columns: [{key, header, align?, flex?, max?, drop?}], rows, footer, empty}
# as lines: framed on a terminal, plain otherwise. A narrow terminal leaves out the drop columns.
def table:
  . as $table
  | (if $isTerminal then $terminalWidth - 3 else $terminalWidth end) as $width
  | $table.rows as $rows
  | ($table.columns | fitColumns($rows; $width)) as {columns: $columns, widths: $widths}
  | ($widths | tableWidth) as $tableWidth
  | (if $isTerminal then "" else " " end) as $indent
  | def line($cells):
      $indent + ([range(0; $columns | length) as $index
              | $cells[$index] | renderCell($widths[$index]; $columns[$index].align // "left")] | join("  "))
      | if $isTerminal then . else sub(" +$"; "") end;
    def rule: $indent + ("─" | times($tableWidth) | paint(dim));
    def header: line([$columns[] | .header | cell(dim)]);
    def body:
      if $rows == [] then $indent + ($table.empty | paint(dim))
      else $rows[] | . as $row | line([$columns[] | $row[.key] // []]) end;
    def footer($footerWidth): ($table.footer | wrapCells($footerWidth; "  ·  " | cell(dim)))[] | $indent + renderInline;
    if $isTerminal then
      "",
      frameTop($table.title | renderInline; $table.subtitle | renderInline; $terminalWidth),
      ((header, rule, if $rows == [] then empty else body end) | frameRow($tableWidth; $terminalWidth)),
      (if $rows == [] then body | frameLine($terminalWidth) else empty end),
      (if $table.footer == [] then empty
       else frameDivider($terminalWidth), (footer($terminalWidth - 4) | frameLine($terminalWidth)) end),
      frameBottom($terminalWidth)
    else
      "",
      " " + ($table.title | renderInline),
      (if $table.subtitle == [] then empty else " " + ($table.subtitle | renderInline) end),
      "",
      header,
      rule,
      body,
      (if $table.footer == [] then empty else rule, footer(infinite) end)
    end;
