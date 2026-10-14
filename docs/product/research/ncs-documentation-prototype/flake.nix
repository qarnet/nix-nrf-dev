{
  description = "Portable tooling and public HTML documentation build for NCS v3.4.1";

  # Save this file AND flake.lock. No relative source files or installed SDK are
  # needed. Source acquisition happens only when the prepare app is invoked.
  #
  #   nix run path:.#prepare -- /absolute/path/to/ncs-v3.4.1
  #   nix run path:.#build-docs -- /absolute/path/to/ncs-v3.4.1
  #   nix run path:.#build-full -- /absolute/path/to/ncs-v3.4.1
  #   nix run path:.#serve-docs -- /absolute/path/to/ncs-v3.4.1/doc-build-v3.4.1/html
  #   nix develop path:.
  #
  # build-docs is compiler-free and skips hardware tables. build-full adds the
  # compiler SDK only to configure boards for those tables (no firmware flash).
  # Both build all public docsets and full devicetree bindings. Kconfig changes
  # against the previous release are opt-in: --kconfig-diff executes downloaded
  # trusted Python/pickle input. Internal/private Nordic documentation is excluded.
  # The SDK workspace and output remain outside the store and may be reused.
  # Remote intersphinx inventories mean output is not byte-for-byte reproducible.
  #
  # path:. also includes these files while they are untracked inside sdk-nrf.
  # Builds run outside the Nix sandbox: TF-M fetches intersphinx inventories.
  # This flake provides tooling/apps, not a hermetic packages.docs derivation.
  # Match the inspected nix-nrf-dev baseline, not a moving unstable channel.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/643809054d65fdd466a63e3155b8c498cb483c04";
  # Only build-full uses the compiler SDK package. Normal apps do not realize
  # the firmware shell, OpenOCD, nrfutil, or contributor tooling.
  inputs.nix-nrf-dev = {
    url = "github:qarnet/nix-nrf-dev/94f7371646f56d5fb46bf32406cdef817f52b85b";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    nixpkgs,
    nix-nrf-dev,
    ...
  }: let
    ncsVersion = "v3.4.1";
    nrfRevision = "b20f8619ba9a5530f8c34b0a130d829947cfe55d";
    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    forAllSystems = nixpkgs.lib.genAttrs systems;
    perSystem = system: let
      pkgs = import nixpkgs {inherit system;};
      # Wheel inputs are exact versions and hashes, not live pip resolution.
      # Isolate documentation packages; do not globally downgrade Sphinx in
      # unrelated Nixpkgs build/test dependencies.
      python = pkgs.python312;
      docPackages = let
        final = python.pkgs // custom;
        wheel = {
          pname,
          version,
          url,
          hash,
          dependencies ? [],
          imports,
        }:
          python.pkgs.buildPythonPackage {
            inherit pname version dependencies;
            format = "wheel";
            src = pkgs.fetchurl {inherit url hash;};
            pythonImportsCheck = imports;
          };
        custom = {
          # Avoid unrelated Azure tracing/test extras (including SciPy).
          azure-core = wheel {
            pname = "azure-core";
            version = "1.38.0";
            url = "https://files.pythonhosted.org/packages/fc/d8/b8fcba9464f02b121f39de2db2bf57f0b216fe11d014513d666e8634380d/azure_core-1.38.0-py3-none-any.whl";
            hash = "sha256:ab0c9b2cd71fecb1842d52c965c95285d3cfb38902f6766e4a471f1cd8905335";
            dependencies = with final; [
              requests
              typing-extensions
            ];
            imports = ["azure.core"];
          };
          azure-storage-blob = wheel {
            pname = "azure-storage-blob";
            version = "12.28.0";
            url = "https://files.pythonhosted.org/packages/d8/3a/6ef2047a072e54e1142718d433d50e9514c999a58f51abfff7902f3a72f8/azure_storage_blob-12.28.0-py3-none-any.whl";
            hash = "sha256:00fb1db28bf6a7b7ecaa48e3b1d5c83bfadacc5a678b77826081304bd87d6461";
            dependencies = with final; [
              azure-core
              cryptography
              typing-extensions
              isodate
            ];
            imports = ["azure.storage.blob"];
          };
          sphinx = wheel {
            pname = "sphinx";
            version = "8.1.3";
            url = "https://files.pythonhosted.org/packages/26/60/1ddff83a56d33aaf6f10ec8ce84b4c007d9368b21008876fceda7e7381ef/sphinx-8.1.3-py3-none-any.whl";
            hash = "sha256:09719015511837b76bf6e03e42eb7595ac8c2e41eeb9c29c5b755c6b677992a2";
            dependencies = with final; [
              alabaster
              babel
              docutils
              imagesize
              jinja2
              packaging
              pygments
              requests
              snowballstemmer
              sphinxcontrib-applehelp
              sphinxcontrib-devhelp
              sphinxcontrib-htmlhelp
              sphinxcontrib-jsmath
              sphinxcontrib-qthelp
              sphinxcontrib-serializinghtml
            ];
            imports = ["sphinx"];
          };
          docutils = wheel {
            pname = "docutils";
            version = "0.21.2";
            url = "https://files.pythonhosted.org/packages/8f/d7/9322c609343d929e75e7e5e6255e614fcc67572cfd083959cdef3b7aad79/docutils-0.21.2-py3-none-any.whl";
            hash = "sha256:dafca5b9e384f0e419294eb4d2ff9fa826435bf15f15b7bd45723e8ad76811b2";
            imports = ["docutils"];
          };
          snowballstemmer = wheel {
            pname = "snowballstemmer";
            version = "2.2.0";
            url = "https://files.pythonhosted.org/packages/ed/dc/c02e01294f7265e63a7315fe086dd1df7dacb9f840a804da846b96d01b96/snowballstemmer-2.2.0-py2.py3-none-any.whl";
            hash = "sha256:c8e1716e83cc398ae16824e5572ae04e0d9fc2c6b985fb0f900f5f0c96ecba1a";
            imports = ["snowballstemmer"];
          };
          sphinx-ncs-theme = wheel {
            pname = "sphinx-ncs-theme";
            version = "2.0.5";
            url = "https://files.pythonhosted.org/packages/fa/10/facacbaca72aa3a68fb35c970e65c48fdc131a1fad5f913a80016074370a/sphinx_ncs_theme-2.0.5-py3-none-any.whl";
            hash = "sha256:f9fa4e3348f8ecae35cc6371e59dc15bf343d8467d8b3cdaf15d174e0d329205";
            dependencies = [final.sphinx-rtd-theme];
            imports = ["sphinx_ncs_theme"];
          };
          # Install the released extension wheels with explicit runtime
          # dependencies. Their upstream Nixpkgs doc/test extras target
          # newer Sphinx and are not part of this documentation runtime.
          sphinx-autobuild = wheel {
            pname = "sphinx-autobuild";
            version = "2025.8.25";
            url = "https://files.pythonhosted.org/packages/d7/20/56411b52f917696995f5ad27d2ea7e9492c84a043c5b49a3a3173573cd93/sphinx_autobuild-2025.8.25-py3-none-any.whl";
            hash = "sha256:b750ac7d5a18603e4665294323fd20f6dcc0a984117026d1986704fa68f0379a";
            dependencies = with final; [
              sphinx
              colorama
              starlette
              uvicorn
              watchfiles
              websockets
            ];
            imports = ["sphinx_autobuild"];
          };
          sphinx-copybutton = wheel {
            pname = "sphinx-copybutton";
            version = "0.5.2";
            url = "https://files.pythonhosted.org/packages/9e/48/1ea60e74949eecb12cdd6ac43987f9fd331156388dcc2319b45e2ebb81bf/sphinx_copybutton-0.5.2-py3-none-any.whl";
            hash = "sha256:fb543fd386d917746c9a2c50360c7905b605726b9355cd26e9974857afeae06e";
            dependencies = [final.sphinx];
            imports = ["sphinx_copybutton"];
          };
          sphinx-rtd-theme = wheel {
            pname = "sphinx-rtd-theme";
            version = "3.1.0";
            url = "https://files.pythonhosted.org/packages/87/c7/b5c8015d823bfda1a346adb2c634a2101d50bb75d421eb6dcb31acd25ebc/sphinx_rtd_theme-3.1.0-py2.py3-none-any.whl";
            hash = "sha256:1785824ae8e6632060490f67cf3a72d404a85d2d9fc26bce3619944de5682b89";
            dependencies = with final; [
              sphinx
              docutils
              sphinxcontrib-jquery
            ];
            imports = ["sphinx_rtd_theme"];
          };
          sphinx-notfound-page = wheel {
            pname = "sphinx-notfound-page";
            version = "1.1.0";
            url = "https://files.pythonhosted.org/packages/cd/d4/019fe439c840a7966012bbb95ccbdd81c5c10271749706793b43beb05145/sphinx_notfound_page-1.1.0-py3-none-any.whl";
            hash = "sha256:835dc76ff7914577a1f58d80a2c8418fb6138c0932c8da8adce4d9096fbcd389";
            dependencies = [final.sphinx];
            imports = ["notfound.extension"];
          };
          sphinx-tabs = wheel {
            pname = "sphinx-tabs";
            version = "3.5.0";
            url = "https://files.pythonhosted.org/packages/2e/45/6adc5efeb19fd5fed4027e520b5c668ce58236a2b271ade5533c4c116276/sphinx_tabs-3.5.0-py3-none-any.whl";
            hash = "sha256:154be49de4d5c8249ea08c5d9bf88ca8f9c31e00a178305a93cbc33e000339e5";
            dependencies = with final; [
              sphinx
              pygments
              docutils
            ];
            imports = ["sphinx_tabs.tabs"];
          };
          sphinx-togglebutton = wheel {
            pname = "sphinx-togglebutton";
            version = "0.4.5";
            url = "https://files.pythonhosted.org/packages/d8/2e/3dd55564928c5d61f92827d4b91307dde7911a40fbe0000645d73202eea9/sphinx_togglebutton-0.4.5-py3-none-any.whl";
            hash = "sha256:74eac6d2426110c3e1e6f989a98e07d7823141a335df1ad8a9d637bdf6a7af62";
            dependencies = with final; [
              sphinx
              docutils
              setuptools
              final.wheel
            ];
            imports = ["sphinx_togglebutton"];
          };
          sphinx-markdown-tables = wheel {
            pname = "sphinx-markdown-tables";
            version = "0.0.17";
            url = "https://files.pythonhosted.org/packages/93/8d/8785a36892992582ef8d87c69ab90e26124ab1059c501d93ebecd99d2323/sphinx_markdown_tables-0.0.17-py3-none-any.whl";
            hash = "sha256:2bd0c30779653e4dd120300cbd9ca412c480738cc2241f6dea477a883f299e04";
            dependencies = [
              final.markdown
              final.sphinx
            ];
            imports = ["sphinx_markdown_tables"];
          };
          sphinxcontrib-programoutput = wheel {
            pname = "sphinxcontrib-programoutput";
            version = "0.18";
            url = "https://files.pythonhosted.org/packages/04/2c/7aec6e0580f666d4f61474a50c4995a98abfff27d827f0e7bc8c4fa528f5/sphinxcontrib_programoutput-0.18-py3-none-any.whl";
            hash = "sha256:8a651bc85de69a808a064ff0e48d06c12b9347da4fe5fdb1e94914b01e1b0c36";
            dependencies = [final.sphinx];
            imports = ["sphinxcontrib.programoutput"];
          };
          sphinxcontrib-jquery = wheel {
            pname = "sphinxcontrib-jquery";
            version = "4.1";
            url = "https://files.pythonhosted.org/packages/76/85/749bd22d1a68db7291c89e2ebca53f4306c3f205853cf31e9de279034c3c/sphinxcontrib_jquery-4.1-py2.py3-none-any.whl";
            hash = "sha256:f936030d7d0147dd026a4f2b5a57343d233f1fc7b363f68b3d4f1cb0993878ae";
            dependencies = [final.sphinx];
            imports = ["sphinxcontrib.jquery"];
          };
          recommonmark = wheel {
            pname = "recommonmark";
            version = "0.7.1";
            url = "https://files.pythonhosted.org/packages/c6/77/ed589c75db5d02a77a1d5d2d9abc63f29676467d396c64277f98b50b79c2/recommonmark-0.7.1-py2.py3-none-any.whl";
            hash = "sha256:1b1db69af0231efce3fa21b94ff627ea33dee7079a01dd0a7f8482c3da148b3f";
            dependencies = with final; [
              sphinx
              docutils
              commonmark
            ];
            imports = ["recommonmark"];
          };
          sphinxcontrib-mscgen = python.pkgs.sphinxcontrib-mscgen.override {inherit (final) sphinx;};
          sphinxcontrib-plantuml = python.pkgs.sphinxcontrib-plantuml.override {inherit (final) sphinx;};
          # m2r2 requires legacy mistune. Keep it private rather than
          # downgrading mistune for unrelated packages in the scope.
          m2r2 = wheel {
            pname = "m2r2";
            version = "0.3.4";
            url = "https://files.pythonhosted.org/packages/a9/50/5b1d70de548fb1e11e15ea9ebec0480365462d202f98b66ad7e154284327/m2r2-0.3.4-py3-none-any.whl";
            hash = "sha256:1a445514af8a229496bfb1380c52da8dd38313e48600359ee92b2c9d2e4df34a";
            dependencies = [
              final.docutils
              (wheel {
                pname = "mistune";
                version = "0.8.4";
                url = "https://files.pythonhosted.org/packages/09/ec/4b43dae793655b7d8a25f76119624350b4d65eb663459eb9603d7f1f0345/mistune-0.8.4-py2.py3-none-any.whl";
                hash = "sha256:88a1051873018da288eee8538d476dffe1262495144b33ecb586c4ab266bb8d4";
                imports = ["mistune"];
              })
            ];
            imports = ["m2r2"];
          };
        };
      in
        final;
      pythonEnv = python.withPackages (
        _:
          with docPackages; [
            # sdk-nrf/doc/requirements.txt at the pinned revision.
            anytree
            azure-storage-blob
            beautifulsoup4
            doxmlparser
            m2r2
            natsort
            pyyaml
            pykwalify
            pytest
            recommonmark
            snowballstemmer
            sphinx
            sphinx-autobuild
            sphinx-copybutton
            sphinx-ncs-theme
            sphinx-notfound-page
            sphinx-tabs
            sphinx-togglebutton
            sphinx-markdown-tables
            sphinxcontrib-mscgen
            sphinxcontrib-plantuml
            sphinxcontrib-programoutput
            sphinxcontrib-jquery
            west
            ply
            python-dotenv
            tabulate
            # Zephyr base scripts/autodoc and NCS manifest/Kconfig helpers.
            canopen
            certifi
            intelhex
            jsonschema
            packaging
            patool
            psutil
            pyelftools
            pylink-square
            pyserial
            junitparser
            requests
            reuse
            semver
            tqdm
          ]
      );
      nativeTools = with pkgs; [
        cmake
        ninja
        git
        doxygen
        mscgen
        plantuml
        graphviz
        coreutils
      ];
      runtimeInputs = nativeTools ++ [pythonEnv];
      # Prevent inherited firmware shell/venv variables from selecting a
      # different interpreter or leaking site-packages into this environment.
      cleanPython = ''
        unset PYTHONHOME PYTHONPATH VIRTUAL_ENV WEST_CONFIG_LOCAL ZEPHYR_BASE Zephyr_DIR
        export PYTHONNOUSERSITE=1
        export WEST_CONFIG_GLOBAL=/dev/null WEST_CONFIG_SYSTEM=/dev/null
      '';
      prepare = pkgs.writeShellApplication {
        name = "prepare-ncs-docs";
        inherit runtimeInputs;
        text = ''
          ${cleanPython}
          if [[ $# -eq 1 && $1 == --help ]]; then
            printf '%s\n' 'Usage: prepare WORKSPACE' \
              'Downloads the public NCS v3.4.1 west projects and manifest-selected submodules.' \
              'WORKSPACE must not exist. Does not install a firmware compiler or pip packages.'
            exit 0
          fi
          if [[ $# -ne 1 ]]; then
            printf '%s\n' 'Usage: prepare WORKSPACE (see --help)' >&2
            exit 2
          fi
          workspace=$(realpath -m -- "$1")
          if [[ -e "$workspace" || -L "$workspace" ]]; then
            printf 'Refusing existing workspace: %s\n' "$workspace" >&2
            exit 2
          fi
          mkdir -p -- "$(dirname -- "$workspace")"
          west init -m https://github.com/nrfconnect/sdk-nrf \
            --mr ${nrfRevision} "$workspace"
          cd -- "$workspace"
          west update
          # Preserve resolved project commits for inspection/recovery.
          west manifest --freeze > documentation-west-frozen.yml
          printf 'Prepared %s at %s\n' '${ncsVersion}' "$workspace"
        '';
      };
      buildDocs = pkgs.writeShellApplication {
        name = "build-ncs-docs";
        inherit runtimeInputs;
        text = ''
          ${cleanPython}
          usage() {
            printf '%s\n' \
              'Usage: build-docs WORKSPACE [--output DIR] [--jobs N] [--kconfig-diff]' \
              '                    [--hardware-features --zephyr-sdk SDK_DIR]' \
              'Builds all public HTML docsets and full devicetree bindings.' \
              'Hardware tables require a compiler SDK; use the build-full app.' \
              'Default output: WORKSPACE/doc-build-v3.4.1; default jobs: 2.' \
              'Needs network access for TF-M intersphinx inventories.' \
              '--kconfig-diff downloads and EXECUTES trusted previous-release Python/pickle data.' \
              'No repository updates or Python installations occur during this command.'
          }
          if [[ $# -eq 1 && $1 == --help ]]; then usage; exit 0; fi
          if [[ $# -lt 1 ]]; then usage >&2; exit 2; fi
          workspace=$(realpath -e -- "$1")
          shift
          output="$workspace/doc-build-${ncsVersion}"
          jobs=2
          kconfig_diff=OFF
          hardware_features=OFF
          sdk_dir=
          while [[ $# -gt 0 ]]; do
            case "$1" in
              --output|--jobs|--zephyr-sdk)
                if [[ $# -lt 2 || -z "$2" ]]; then usage >&2; exit 2; fi
                case "$1" in
                  --output) output=$(realpath -m -- "$2") ;;
                  --jobs) jobs=$2 ;;
                  --zephyr-sdk) sdk_dir=$(realpath -e -- "$2") ;;
                esac
                shift 2
                ;;
              --kconfig-diff) kconfig_diff=ON; shift ;;
              --hardware-features) hardware_features=ON; shift ;;
              *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
            esac
          done
          if [[ ! $jobs =~ ^[1-9][0-9]*$ ]]; then
            printf '%s\n' '--jobs must be a positive integer' >&2; exit 2
          fi
          if [[ $hardware_features == ON && ! -f "$sdk_dir/cmake/Zephyr-sdkConfig.cmake" ]]; then
            printf '%s\n' 'Hardware tables require --zephyr-sdk with a prepared Zephyr SDK.' >&2; exit 2
          fi
          if [[ ! -f "$workspace/.west/config" || ! -f "$workspace/nrf/doc/CMakeLists.txt" ]]; then
            printf '%s\n' 'Expected a prepared west workspace with manifest at nrf/.' >&2; exit 2
          fi
          revision=$(git -C "$workspace/nrf" rev-parse HEAD)
          if [[ $revision != ${nrfRevision} ]]; then
            printf 'Expected sdk-nrf %s (%s), found %s\n' '${ncsVersion}' '${nrfRevision}' "$revision" >&2
            exit 2
          fi
          if [[ ! -f "$workspace/zephyr/share/zephyr-package/cmake/ZephyrConfig.cmake" ]]; then
            printf '%s\n' 'Matched Zephyr sources missing; complete west update first.' >&2; exit 2
          fi
          cd -- "$workspace"
          export ZEPHYR_BASE="$workspace/zephyr"
          unset Zephyr_DIR
          # gen_boards_catalog.py forwards PATH but strips SDK environment
          # variables before running Twister. A build-local CMake wrapper
          # restores the explicitly selected SDK without patching sources or
          # registering anything in the user's global CMake package registry.
          if [[ $hardware_features == ON ]]; then
            tools="$output/.doc-host-tools"
            mkdir -p -- "$tools"
            {
              printf '#!%s\n' '${pkgs.bash}/bin/bash'
              printf 'export ZEPHYR_TOOLCHAIN_VARIANT=zephyr\n'
              printf 'export ZEPHYR_SDK_INSTALL_DIR=%q\n' "$sdk_dir"
              printf '%s\n' 'exec ${pkgs.cmake}/bin/cmake "$@"'
            } > "$tools/cmake"
            chmod +x -- "$tools/cmake"
            export PATH="$tools:$PATH"
          fi
          cmake -G Ninja -S "$workspace/nrf/doc" -B "$output" \
            -DZephyr_DIR="$ZEPHYR_BASE/share/zephyr-package/cmake" \
            -DPython_EXECUTABLE=${pythonEnv}/bin/python3 \
            -DPYTHON_EXECUTABLE=${pythonEnv}/bin/python3 \
            -DPython3_EXECUTABLE=${pythonEnv}/bin/python3 \
            -DDTS_BINDINGS=ON -DHW_FEATURES="$hardware_features" \
            -DKCONFIGDIFF="$kconfig_diff" -DNCS_RELEASE=ON \
            -DSPHINXOPTS="-j $jobs -W --keep-going -T"
          # Only one docset at a time; each Sphinx process gets jobs workers.
          cmake --build "$output" --target build-all --parallel 1
          for page in index.html nrf/index.html zephyr/index.html mcuboot/wrapper.html; do
            if [[ ! -s "$output/html/$page" ]]; then
              printf 'Missing required output: %s\n' "$output/html/$page" >&2; exit 1
            fi
          done
          printf 'Documentation built: %s/html\n' "$output"
        '';
      };
      buildFull = pkgs.writeShellApplication {
        name = "build-full-ncs-docs";
        runtimeInputs = [buildDocs];
        text = ''
          if [[ $# -eq 0 ]]; then
            printf '%s\n' 'Usage: build-full WORKSPACE [--output DIR] [--jobs N] [--kconfig-diff]' >&2
            exit 2
          fi
          if [[ $# -eq 1 && $1 == --help ]]; then
            printf '%s\n' 'Usage: build-full WORKSPACE [--output DIR] [--jobs N] [--kconfig-diff]' \
              'Like build-docs, with hardware tables and the pinned nix-nrf-dev compiler SDK.' \
              'First use downloads the Zephyr SDK/compiler packages through Nix.'
            exit 0
          fi
          exec build-ncs-docs "$@" --hardware-features \
            --zephyr-sdk ${nix-nrf-dev.packages.${system}.west-zephyr-sdk-v3_4_1}
        '';
      };
      serveDocs = pkgs.writeShellApplication {
        name = "serve-ncs-docs";
        runtimeInputs = [
          pythonEnv
          pkgs.coreutils
        ];
        text = ''
          ${cleanPython}
          if [[ $# -eq 1 && $1 == --help ]]; then
            printf '%s\n' 'Usage: serve-docs HTML_DIR [PORT]' 'Serves on 127.0.0.1 only; default port 8000.'
            exit 0
          fi
          if [[ $# -lt 1 || $# -gt 2 ]]; then
            printf '%s\n' 'Usage: serve-docs HTML_DIR [PORT]' >&2; exit 2
          fi
          html=$(realpath -e -- "$1")
          port=''${2:-8000}
          if [[ ! -f "$html/index.html" || ! $port =~ ^[0-9]{1,5}$ ]]; then
            printf '%s\n' 'Expected HTML output with index.html and a port from 1 to 65535.' >&2; exit 2
          fi
          if (( 10#$port < 1 || 10#$port > 65535 )); then
            printf '%s\n' 'Port must be from 1 to 65535.' >&2; exit 2
          fi
          exec python3 -m http.server "$port" --bind 127.0.0.1 --directory "$html"
        '';
      };
      commandCheck =
        pkgs.runCommand "ncs-doc-command-check"
        {
          nativeBuildInputs = [
            pythonEnv
            prepare
            buildDocs
            serveDocs
          ];
        }
        ''
          ${cleanPython}
          python3 - <<'PY'
          from pathlib import Path
          import socket
          import subprocess
          import tempfile
          import time
          import urllib.request

          def run(*args, code=0):
              result = subprocess.run(args, capture_output=True, text=True)
              assert result.returncode == code, (args, result.returncode, result.stderr)
              return result.stdout

          for app in ["prepare-ncs-docs", "build-ncs-docs", "serve-ncs-docs"]:
              assert "Usage:" in run(app, "--help")
              run(app, code=2)
          with tempfile.TemporaryDirectory() as root:
              root = Path(root)
              sentinel = root / "keep.txt"
              sentinel.write_text("unchanged")
              run("prepare-ncs-docs", str(root), code=2)
              assert sentinel.read_text() == "unchanged"
              assert not (root / ".west").exists()
              run("build-ncs-docs", str(root), code=2)
              run("build-ncs-docs", str(root), "--jobs", "0", code=2)
              run("build-ncs-docs", str(root), "--output", code=2)
              run("build-ncs-docs", str(root), "--unknown", code=2)
              run("build-ncs-docs", str(root), "--hardware-features", code=2)
              run("serve-ncs-docs", str(root), code=2)
              (root / "index.html").write_text("<h1>Public HTTP boundary</h1>")
              for port in ["0", "65536", "bad"]:
                  run("serve-ncs-docs", str(root), port, code=2)
              with socket.socket() as sock:
                  sock.bind(("127.0.0.1", 0))
                  port = sock.getsockname()[1]
              process = subprocess.Popen(["serve-ncs-docs", str(root), str(port)],
                                         stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
              try:
                  opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
                  deadline = time.monotonic() + 10
                  while True:
                      try:
                          with opener.open(f"http://127.0.0.1:{port}/", timeout=1) as response:
                              assert response.status == 200
                              assert b"Public HTTP boundary" in response.read()
                          break
                      except OSError:
                          assert process.poll() is None, process.stderr.read().decode()
                          if time.monotonic() >= deadline:
                              raise
                          time.sleep(0.1)
              finally:
                  process.terminate()
                  process.wait(timeout=5)
              assert sentinel.read_text() == "unchanged"
          PY
          touch "$out"
        '';
      toolCheck =
        pkgs.runCommand "ncs-doc-tools-check"
        {
          nativeBuildInputs = runtimeInputs;
        }
        ''
          ${cleanPython}
          python3 - <<'PY'
          from importlib import import_module, metadata
          from packaging.requirements import Requirement

          # Bounded constraints in v3.4.1 doc/requirements.txt and SDK base.
          for text in ["sphinx>=8.1,<8.2", "snowballstemmer<3", "sphinx-ncs-theme<2.1",
                       "sphinx-notfound-page>=1", "sphinx-tabs>=3.4",
                       "sphinxcontrib-plantuml>=0.27", "west>=1.4"]:
              req = Requirement(text)
              assert metadata.version(req.name) in req.specifier, text
          for module in ["sphinx", "sphinx_ncs_theme", "m2r2", "recommonmark",
                         "doxmlparser", "west.manifest", "yaml", "pykwalify",
                            "dotenv", "requests", "jsonschema", "junitparser.junitparser", "sphinx_tabs.tabs",
                         "sphinxcontrib.mscgen", "sphinxcontrib.plantuml",
                         "sphinxcontrib.programoutput", "sphinx_markdown_tables"]:
              import_module(module)
          # Check runtime dependency metadata, not only top-level versions.
          for dist in metadata.distributions():
              for text in dist.requires or []:
                  req = Requirement(text)
                  if req.marker is None or req.marker.evaluate({"extra": ""}):
                      assert metadata.version(req.name) in req.specifier, (dist.name, text)
          PY
          # Prove that Markdown and Nordic theme render through public Sphinx CLI.
          mkdir source
           printf '%s\n' 'extensions = ["m2r2"]' \
             'source_suffix = {".rst": "restructuredtext", ".md": "markdown"}' \
             'html_theme = "sphinx_ncs_theme"' \
             'html_theme_options = {"docset": "nrf", "docsets": {"nrf": ("NCS", "index", "manifest")}}' \
             > source/conf.py
          printf '%s\n' '# Documentation tool smoke test' "" 'Rendered Markdown.' > source/index.md
          sphinx-build -W -b html source html
          test -s html/index.html
          doxygen --version
          command -v mscgen plantuml dot west
          touch "$out"
        '';
    in {
      packages = {
        default = pythonEnv;
        python = pythonEnv;
        inherit prepare;
        build-docs = buildDocs;
        build-full = buildFull;
        serve-docs = serveDocs;
      };
      apps =
        builtins.mapAttrs
        (_: package: {
          type = "app";
          meta.description = "NCS v3.4.1 documentation command; invoke with --help";
          program = "${package}/bin/${package.meta.mainProgram}";
        })
        {
          inherit prepare;
          build-docs = buildDocs;
          build-full = buildFull;
          serve-docs = serveDocs;
        };
      checks = {
        tools = toolCheck;
        commands = commandCheck;
        inherit prepare buildDocs serveDocs;
      };
      devShell = pkgs.mkShell {
        packages =
          runtimeInputs
          ++ [
            prepare
            buildDocs
            serveDocs
          ];
        shellHook = ''
          ${cleanPython}
          printf '%s\n' 'NCS v3.4.1 documentation tools ready; no sources downloaded.' \
            'Commands: prepare-ncs-docs, build-ncs-docs, serve-ncs-docs (each accepts --help).'
        '';
      };
    };
  in {
    packages = forAllSystems (system: (perSystem system).packages);
    apps = forAllSystems (system: (perSystem system).apps);
    checks = forAllSystems (system: (perSystem system).checks);
    devShells = forAllSystems (system: {
      default = (perSystem system).devShell;
    });
  };
}
