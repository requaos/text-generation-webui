{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs_cmake.url = "github:nixos/nixpkgs/nixos-22.11";
    nixpkgs_hardware.url = "github:nixos/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
    poetry2nix = {
      url = "github:nix-community/poetry2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, nixpkgs_cmake, nixpkgs_hardware, utils, poetry2nix, ... }:
    let out = system:
      let
        cudaSupport = true;
        pkgs = import nixpkgs {
          inherit system;
          config.cudaSupport = cudaSupport;
          config.allowUnfree = true;
        };
        cuda_pkgs = import nixpkgs_hardware {
          inherit system;
          config.cudaSupport = cudaSupport;
          config.allowUnfree = true;
        };
        test_pkgs = import nixpkgs_cmake {
          inherit system;
        };
        lib = pkgs.lib;
        inherit (pkgs.cudaPackages) cudatoolkit;
        inherit (pkgs.linuxPackages) nvidia_x11;
        inherit (poetry2nix.legacyPackages.${system}) mkPoetryEnv;
        withDefaults = poetry2nix.legacyPackages.${system}.overrides.withDefaults;
        magma = cuda_pkgs.magma.override {
          inherit cudaSupport;
        };
        python = pkgs.python310;
        pythonEnv = mkPoetryEnv {
          inherit python;
          projectDir = ./.;
          preferWheels = true;
          groups = ["nvidia" "mpt"];
          extras = [];
          overrides = withDefaults (
            self: super: {
              bitsandbytes = import ./bitsandbytes.nix {
                inherit lib python;
                inherit (pkgs) fetchFromGitHub pytestCheckHook symlinkJoin;
                inherit (pkgs.python310.pkgs) buildPythonPackage pythonOlder setuptools;
                inherit (self) torch einops lion-pytorch scipy;
              };
              gradio = super.gradio.overridePythonAttrs (old: {
                propagatedBuildInputs = (old.propagatedBuildInputs or [ ]) ++ [super.setuptools];
              });
              pybind11 = pkgs.python310Packages.pybind11;
              lit = super.lit.overridePythonAttrs (old: {
                buildInputs = (old.buildInputs or [ ]) ++ [ super.setuptools ];
              });
              nvidia-cuda-nvrtc-cu11 = super.nvidia-cuda-nvrtc-cu11.overridePythonAttrs (old: {
                buildInputs = (old.buildInputs or [ ]) ++ [ cuda_pkgs.cudaPackages.cuda_nvrtc ];
              });
              sphinxcontrib-jquery = super.sphinxcontrib-jquery.overridePythonAttrs (old: {
                buildInputs = (old.buildInputs or [ ]) ++ [ super.setuptools super.sphinx ];
              });
              tensorboard = super.tensorboard.overridePythonAttrs (old: {
                buildInputs = (old.buildInputs or [ ]) ++ [ super.setuptools ];
              });
              triton = (pkgs.python310Packages.openai-triton-bin.override {
                inherit python;
                inherit (cuda_pkgs) cudaPackages;
                inherit (super) filelock;
                inherit (self) lit;
              });
              torch = pkgs.python310Packages.torch.override {
                inherit python cudaSupport magma;
                inherit (cuda_pkgs) cudaPackages blas;
                inherit (super) filelock jinja2 networkx sympy pyyaml click typing-extensions hypothesis;
                inherit (self) numpy pillow six future tensorboard protobuf cffi;
                openai-triton = self.triton;
              };
              torchaudio = (pkgs.python310Packages.torchaudio.override {
                inherit cudaSupport;
                inherit (cuda_pkgs) cudaPackages;
                inherit (self) pybind11 torch;
              }).overrideAttrs (oldAttrs: {
                buildInputs = oldAttrs.buildInputs ++ lib.optionals cudaSupport [
                  cuda_pkgs.cudaPackages.cuda_cudart
                ];
              });
            }
          );
        };
        commonPackages = [
          pythonEnv
          pkgs.poetry
        ];
        openai-triton = pkgs.python310Packages.openai-triton-bin.override {
          inherit python;
          inherit (cuda_pkgs) cudaPackages;
        };
        torch = pkgs.python310Packages.torch.override {
          inherit python cudaSupport magma;
          inherit (cuda_pkgs) cudaPackages blas;
        };
      in
      {
        devShells ={
          default = pkgs.mkShell {
            buildInputs = commonPackages;
            shellHook = let
              cudatoolkit = cuda_pkgs.cudaPackages.cudatoolkit;
              nvidia_x11 = cuda_pkgs.linuxPackages.nvidia_x11;
              nvtrc = cuda_pkgs.cudaPackages.cuda_nvrtc;
            in ''
              export CUDA_PATH=${cudatoolkit.lib}
              export LD_LIBRARY_PATH="${cudatoolkit.lib}/lib:${nvidia_x11}/lib:$LD_LIBRARY_PATH"
              export LD_LIBRARY_PATH="${nvtrc}/lib:$LD_LIBRARY_PATH"
            '';
          };
        };
      }; in with utils.lib; eachSystem defaultSystems out;
}
