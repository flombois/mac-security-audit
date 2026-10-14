# The report's tables, built from the slurped results; expects $host, $macos and $generatedAt.

def statusStyle: {run: "", skipped: dim, error: magenta}[.];
def outcomeStyle: {pass: green, fail: red}[.];
def severityStyle: {high: red, medium: yellow, low: blue}[.];
def severities: ["high", "medium", "low"];

def badge(style): if . == null then [] else . as $value | ascii_upcase | cell($value | style) end;

def arrow: if . == "" then "" else "→ \(.)" end;

# Usage: tallies("status"; ["run", "skipped"]; statusStyle); "3 run  ·  1 skipped", leaving out the zero counts.
def tallies($key; $values; style):
  . as $results
  | [$values[] as $value | $results | map(select(.[$key] == $value)) | length | tally($value; $value | style)];

def reportTable($title; $columns; $rows; $footer):
  {title: ("\($title) (\($rows | length))" | cell(bold)), subtitle: [], columns: $columns, rows: $rows,
   footer: $footer, empty: "none"};

# Every check in run order; a manual check's detail ends with what to review.
def checks:
  . as $results
  | reportTable("Checks";
      [{key: "status", header: "STATUS"}, {key: "outcome", header: "OUTCOME"},
       {key: "id", header: "ID"}, {key: "check", header: "CHECK", max: 40, drop: true},
       {key: "detail", header: "DETAIL", flex: true}];
      [$results[]
       | {status: (.status | badge(statusStyle)), outcome: (.outcome | badge(outcomeStyle)),
          id: (.id | cell(dim)), check: (.title | cell("")),
          detail: ([.detail, (select(.status == "skipped" and .remediation != "") | .remediation | arrow)] | join(" ") | cell(""))}];
      ($results | tallies("status"; ["run", "skipped", "error"]; statusStyle))
        + ($results | tallies("outcome"; ["pass", "fail"]; outcomeStyle)))
  | .subtitle = ("\($host) · macOS \($macos) · \($generatedAt)" | cell(dim));

# The failed checks, most severe first.
def findings:
  [severities[] as $severity | .[] | select(.severity == $severity)] as $results
  | reportTable("Findings";
      [{key: "severity", header: "SEVERITY"}, {key: "id", header: "ID"},
       {key: "check", header: "CHECK", max: 40, drop: true}, {key: "detail", header: "DETAIL", max: 40, drop: true},
       {key: "risk", header: "RISK", max: 50, drop: true}, {key: "fix", header: "FIX", flex: true}];
      [$results[]
       | {severity: (.severity | badge(severityStyle)), id: (.id | cell(dim)),
          check: (.title | cell("")), detail: (.detail | cell("")), risk: (.risk // "" | cell("")),
          fix: (.remediation | arrow | cell(""))}];
      $results | tallies("severity"; severities; severityStyle));

# The --interactive browse

# A result's word: its severity when it failed, else its outcome or status.
def verdict:
  if .severity then .severity | badge(severityStyle)
  elif .outcome then .outcome | badge(outcomeStyle)
  else .status | badge(statusStyle) end;

# Tab-separated lines of each kept result's index in the results and its row; findings come most severe first.
def browseRows($list):
  [to_entries[] | select($list == "checks" or .value.severity != null)]
  | if $list == "checks" then . else [severities[] as $severity | .[] | select(.value.severity == $severity)] end
  | ([.[].value.id | textWidth] | max // 0) as $idWidth
  | ([.[].value.title | textWidth] | max // 0 | [., 50] | min) as $titleWidth
  | .[]
  | "\(.key)\t" + (.value | verdict | renderCell(9; "left")) + (.value.id | cell(dim) | renderCell($idWidth + 2; "left"))
    + (.value.title | cell("") | renderCell($titleWidth + 2; "left")) + (.value.detail | paint(dim));

# Everything about one result, for the preview and the full view.
def detail:
  def section($heading; $lines): if $lines == [] then empty else "", ($heading | paint(bold)), ($lines[] | "  \(.)") end;
  (.title | paint(bold)),
  (.id | paint(dim)),
  "",
  ([(.status | badge(statusStyle)), (.outcome | badge(outcomeStyle)), (.severity | badge(severityStyle))]
   | map(select(. != []) | renderInline) | join("  ·  ")),
  section("Detail"; [.detail | select(. != "")]),
  section("Why it matters"; [.risk // empty]),
  section("Impact"; [.impact // empty]),
  section(if .status == "skipped" then "To do" else "Fix" end; [.remediation | select(. != "")]),
  section("Commands run"; [.commands // [] | .[] | "$ \(printable)"]);
