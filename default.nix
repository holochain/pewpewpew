# This is an example of what downstream consumers of holonix should do
# This is also used to dogfood as many commands as possible for holonix
# For example the release process for holonix uses this file
let

 # point this to your local config.nix file for this project
 # example.config.nix shows and documents a lot of the options
 config = import ./config.nix;

 # START HOLONIX IMPORT BOILERPLATE
 holonix = import (
  if ! config.holonix.use-github
  then config.holonix.local.path
  else fetchTarball {
   url = "https://github.com/${config.holonix.github.owner}/${config.holonix.github.repo}/tarball/${config.holonix.github.ref}";
   sha256 = config.holonix.github.sha256;
  }
 ) { config = config; use-stable-rust = true; };
 # END HOLONIX IMPORT BOILERPLATE

in
with holonix.pkgs;
{
 dev-shell = stdenv.mkDerivation (holonix.shell // {
  name = "dev-shell";

  shellHook = holonix.pkgs.lib.concatStrings [
   holonix.shell.shellHook
   ''
    export BENCH_OUTPUT_DIR=$PWD/.bench
    export HC_TARGET_PREFIX=$NIX_ENV_PREFIX
    export CARGO_TARGET_DIR="$HC_TARGET_PREFIX/target"
    export HC_TEST_WASM_DIR="$HC_TARGET_PREFIX/.wasm_target"
    mkdir -p $HC_TEST_WASM_DIR
    export CARGO_CACHE_RUSTC_INFO=1

    export HC_WASM_CACHE_PATH="$HC_TARGET_PREFIX/.wasm_cache"
    mkdir -p $HC_WASM_CACHE_PATH

    export PEWPEWPEW_PORT=4343

    touch .env
    source .env
   ''
  ];

  buildInputs = [
   holonix.pkgs.gnuplot
   holonix.pkgs.flamegraph
   holonix.pkgs.fd
   holonix.pkgs.ngrok
   holonix.pkgs.jq
   holonix.pkgs.tmux
  ]
   ++ holonix.shell.buildInputs

   ++ ([(
    holonix.pkgs.writeShellScriptBin "hc-bench" ''
    cargo bench --bench bench
    '')])

   ++ ([(
    holonix.pkgs.writeShellScriptBin "hc-fmt-all" ''
    fd Cargo.toml crates | xargs -L 1 cargo fmt --manifest-path
    '')])

   ++ ([(
    holonix.pkgs.writeShellScriptBin "hc-bench-github" ''
    set -x

    # the first arg is the authentication token for github
    # @todo this is only required because the repo is currently private
    token=''${1}

    # set the target dir to somewhere it is less likely to be accidentally deleted
    CARGO_TARGET_DIR=$BENCH_OUTPUT_DIR

    # run benchmarks from a github archive based on any ref github supports
    # @param ref: the github ref to benchmark
    function bench {

     ## vars
     ref=$1
     dir="$TMP/$ref"
     tarball="$dir/tarball.tar.gz"

     ## process

     ### fresh start
     mkdir -p $dir
     rm -f $dir/$tarball

     ### fetch code to bench
     curl -L --cacert $SSL_CERT_FILE -H "Authorization: token $token" "https://github.com/holochain/holochain/archive/$ref.tar.gz" > $tarball
     tar -zxvf $tarball -C $dir

     cd $dir/holochain-$ref

     ### build wasms
     cargo build --features 'build_wasms' --manifest-path=crates/holochain/Cargo.toml

     ### bench code
     cargo bench --bench bench -- --save-baseline $ref

    }

    # load an existing report and push it as a comment to github
    function add_comment_to_commit {
     ## convert the report to POST-friendly json and push to github comment API
     jq \
      -n \
      --arg report \
      "\`\`\`$( cargo bench --bench bench -- --baseline $1 --load-baseline $2 )\`\`\`" \
      '{body: $report}' \
     | curl \
      -L \
      --cacert $SSL_CERT_FILE \
      -H "Authorization: token $token" \
      -X POST \
      -H "Accept: application/vnd.github.v3+json" \
      https://api.github.com/repos/holochain/holochain/commits/$2/comments \
      -d@-
    }

    commit=''${2}
    bench $commit

    # @todo make this flexible based on e.g. the PR base on github
    compare=develop
    bench $compare
    add_comment_to_commit $compare $commit
    '')])

    ++ ([(
     holonix.pkgs.writeShellScriptBin "pewpewpew" ''
     # compile and build pewpewpew
     cargo run
     '')])

    ++ ([(
     holonix.pkgs.writeShellScriptBin "pewpewpew-detached" ''
      tmux new -d -spewpewpew -- pewpewpew
     '')])

    ++ ([(
     holonix.pkgs.writeShellScriptBin "pewpewpew-attach" ''
      tmux attach -tpewpewpew
    '')])

    ++ ([(
     holonix.pkgs.writeShellScriptBin "pewpewpew-ngrok" ''
     # serve up a local pewpewpew instance that github can point to for testing
     ngrok http -hostname=holochain-pewpewpew.ngrok.io http://127.0.0.1:$PEWPEWPEW_PORT
    '')])

    ++ ([(
     holonix.pkgs.writeShellScriptBin "pewpewpew-ngrok-detached" ''
     tmux new -d -spewpewpew-ngrok -- pewpewpew-ngrok
     '')])

    ++ ([(
     holonix.pkgs.writeShellScriptBin "pewpewpew-ngrok-attach" ''
     tmux attach -tpewpewpew-ngrok
     '')])

    ++ ([(
     holonix.pkgs.writeShellScriptBin "pewpewpew-gen-secret" ''
     # generate a new github secret
     cat /dev/urandom | head -c 64 | base64 -w 0
    '')])
  ;
 });
}
