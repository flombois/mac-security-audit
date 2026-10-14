# Finds installed language runtimes and toolchains; source it, don't run it.
# Versions come from folder names and version files: no runtime is run.

# Prints "runtime<TAB>version<TAB>source" for each installed runtime, once each.
installed_runtimes() {
  {
    java_runtimes
    node_runtimes
    python_runtimes
    go_runtimes
    rust_runtimes
    ruby_runtimes
    c_toolchains
  } | awk -F'\t' '$2 != "" && !seen[$0]++'
}

java_runtimes() {
  local release source
  for release in "$JAVA_VM_DIR"/*/Contents/Home/release "$HOME"/.sdkman/candidates/java/*/release; do
    [[ -e "$release" ]] || continue
    source="$JAVA_VM_DIR"
    [[ "$release" != "$HOME"/.sdkman/* ]] || source=SDKMAN
    printf 'Java\t%s\t%s\n' "$(sed -n 's/^JAVA_VERSION="\(.*\)"/\1/p' "$release" | version_in)" "$source"
  done
  homebrew_versions Java 'openjdk' 'openjdk@*'
  version_manager_versions Java java
}

node_runtimes() {
  folder_versions Node nvm "$HOME"/.nvm/versions/node/*
  folder_versions Node fnm "$HOME/Library/Application Support/fnm/node-versions"/* "$HOME"/.local/share/fnm/node-versions/*
  folder_versions Node Volta "$HOME"/.volta/tools/image/node/*
  folder_versions Node nodenv "$HOME"/.nodenv/versions/*
  folder_versions Node n "${N_PREFIX:-/usr/local}"/n/versions/node/*
  folder_versions Node pnpm "$HOME"/Library/pnpm/nodejs/*
  homebrew_versions Node 'node' 'node@*'
  version_manager_versions Node node nodejs
}

# Versions without a minor number are conda or PyPy distribution names, not Python versions.
python_runtimes() {
  local conda_meta
  {
    homebrew_versions Python 'python@3*'
    folder_versions Python pyenv "$HOME"/.pyenv/versions/*
    folder_versions Python uv "$HOME"/.local/share/uv/python/cpython-*
    folder_versions Python python.org "$PYTHON_ORG_DIR"/[0-9]*
    for conda_meta in "$HOME"/miniconda3 "$HOME"/anaconda3 "$HOME"/miniforge3; do
      folder_versions Python conda "$conda_meta"/conda-meta/python-[0-9]*.json
    done
    version_manager_versions Python python
  } | awk -F'\t' '$2 ~ /\./'
}

go_runtimes() {
  [[ ! -e "$GO_INSTALL_DIR/VERSION" ]] || printf 'Go\t%s\tgo.dev\n' "$(head -1 "$GO_INSTALL_DIR/VERSION" | version_in)"
  homebrew_versions Go 'go' 'go@*'
  folder_versions Go goenv "$HOME"/.goenv/versions/*
  folder_versions Go golang.org/dl "$HOME"/sdk/go1.*
  version_manager_versions Go go golang
}

# rustup toolchains like "stable-aarch64-apple-darwin" name their version in the channel manifest.
rust_runtimes() {
  local manifest
  for manifest in "$HOME"/.rustup/toolchains/*/lib/rustlib/multirust-channel-manifest.toml; do
    [[ -e "$manifest" ]] || continue
    printf 'Rust\t%s\trustup\n' "$(awk '/^\[pkg\.rust\]$/ { in_rust = 1; next } /^\[/ { in_rust = 0 }
      in_rust && /^version = / { print; exit }' "$manifest" | version_in)"
  done
  homebrew_versions Rust 'rust'
  version_manager_versions Rust rust
}

ruby_runtimes() {
  homebrew_versions Ruby 'ruby' 'ruby@*'
  folder_versions Ruby rbenv "$HOME"/.rbenv/versions/*
  folder_versions Ruby rvm "$HOME"/.rvm/rubies/ruby-*
  version_manager_versions Ruby ruby
}

# Never runs clang, gcc, cc or xcrun: without developer tools, they open an install dialog.
c_toolchains() {
  local clt_version
  clt_version="$(pkgutil --pkg-info=com.apple.pkg.CLTools_Executables 2>/dev/null | sed -n 's/^version: //p')"
  [[ -z "$clt_version" ]] || printf 'C/C++\t%s\tCommand Line Tools\n' "$(echo "$clt_version" | cut -d. -f1-2)"
  homebrew_versions C/C++ 'gcc' 'gcc@*' | sed 's/\tHomebrew$/\tGCC, Homebrew/'
  homebrew_versions C/C++ 'llvm' 'llvm@*' | sed 's/\tHomebrew$/\tLLVM, Homebrew/'
}

# Usage: folder_versions runtime source folder...
# Prints the version in each folder's name; symlinks such as "current" are skipped.
folder_versions() {
  local runtime="$1" source="$2" folder
  shift 2
  for folder in "$@"; do
    [[ -e "$folder" && ! -L "$folder" ]] || continue
    printf '%s\t%s\t%s\n' "$runtime" "$(basename "$folder" | version_in)" "$source"
  done
}

# Usage: homebrew_versions runtime formula_glob...
homebrew_versions() {
  local runtime="$1" prefix formula
  shift
  for prefix in $HOMEBREW_PREFIXES; do
    for formula in "$@"; do
      # shellcheck disable=SC2086 # $formula is a glob
      folder_versions "$runtime" Homebrew "$prefix"/Cellar/$formula/*
    done
  done
}

# Usage: version_manager_versions runtime tool_name...
version_manager_versions() {
  local runtime="$1" tool
  shift
  for tool in "$@"; do
    folder_versions "$runtime" mise "$HOME/.local/share/mise/installs/$tool"/*
    folder_versions "$runtime" asdf "$HOME/.asdf/installs/$tool"/*
  done
}

# Prints the first version number in stdin, e.g. 21.0.2 in "temurin-21.0.2+13".
version_in() {
  grep -oE '[0-9]+(\.[0-9]+)*' | head -1
}
