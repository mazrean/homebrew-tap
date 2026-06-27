class Kanata < Formula
  desc "macOS 26 / Apple Silicon K8s node agent with VM-based pod execution"
  homepage "https://github.com/mazrean/kanata"
  url "https://github.com/mazrean/kanata/releases/download/v0.1.0/kanata-v0.1.0-arm64-macos.tar.gz"
  version "0.1.0"
  sha256 "e827612d2fbf14aba2f1185cd5a787c007db95748536e5b0918ee6e0043b6869"

  # Requires macOS 26 (Tahoe) or later
  depends_on macos: :tahoe

  def install
    # Does not run on Intel
    odie "kanata requires Apple Silicon. It does not run on Intel Macs." unless Hardware::CPU.arm?

    # Install binary and SwiftPM resource bundle to bin/
    # bin.install creates symlinks in the Homebrew prefix so that
    # Bundle.main.bundleURL (which returns the symlink directory) can find the bundle.
    bin.install "bin/kanata"
    bin.install "bin/kanata_ControlPlane.bundle"

    # Place runtime dependencies under share/kanata/
    # Tarball layout (ADR §Decision-1): vm.entitlements is bundled as share/kanata/vm.entitlements
    (share/"kanata").mkpath
    (share/"kanata").install "share/kanata/vm.entitlements" => "vm.entitlements"

    # Copy kernel / nat-kernel / gw-image / probe directly under share/kanata/
    (share/"kanata/kernel").mkpath
    (share/"kanata/kernel").install "kernel/vmlinux"

    (share/"kanata/nat-kernel").mkpath
    (share/"kanata/nat-kernel").install "nat-kernel/vmlinux"

    (share/"kanata/gw-image").mkpath
    cp_r "gw-image/.", share/"kanata/gw-image"

    (share/"kanata/probe").mkpath
    (share/"kanata/probe").install "probe/kanata-probe"

    # Re-sign bin/kanata ad-hoc with vm.entitlements
    ["kanata"].each do |b|
      system "codesign", "--force", "--sign", "-",
             "--entitlements", (share/"kanata/vm.entitlements").to_s,
             (bin/b).to_s
    end
  end

  def post_install
    # Create working directories under var/kanata/ (preserve any existing content)
    # plist generation and launchd registration are handled by `kanata create cluster <name>` (ADR-0021 §D-3)
    (var/"kanata/artifacts").mkpath
    (var/"kanata/run").mkpath
  end

  # The `service do` block is intentionally omitted.
  # Each cluster's launchd plist is generated at its per-cluster path by `kanata create cluster`.
  # `brew services` is not used (ADR-0021 §D-3).

  def caveats
    <<~EOS
      kanata requires macOS 26 (Tahoe) and Apple Silicon. It does not run on other platforms.
      It also uses the vmnet framework for virtual networking.

      brew install only installs the binary and runtime resources.
      Clusters must be created and started explicitly with the `kanata create cluster` command.

      --- Creating a cluster ---

      To create a cluster, run:

        kanata create cluster <name>

      Examples:
        kanata create cluster dev
        kanata create cluster staging

      Cluster names must match [a-z0-9-], be at most 63 characters, and must not start or end with a hyphen.

      Once created, the process is registered and started with launchd,
      and the context is appended non-destructively to ~/.kube/config (current-context is not changed).

      --- Managing clusters with kubectl ---

      After creation, check node status with:

        kubectl --context kanata-<name> get nodes

      Example:
        kubectl --context kanata-dev get nodes

      To set a context as the default:

        kubectl config use-context kanata-<name>

      Note: VM startup and control plane initialization take 1-2 minutes.
      If the connection fails, wait a moment and try again.
      Check startup progress at /tmp/kanata-<name>.log.

      --- Listing and deleting clusters ---

      List clusters:
        kanata get clusters

      Delete a cluster (unregisters from launchd and removes state directory):
        kanata delete cluster <name>

      --- Checking logs and status ---

      View logs:
        tail -f /tmp/kanata-<name>.log

      Check startup status:
        launchctl print gui/$(id -u)/io.kanata.kanata.<name>

      --- Uninstalling ---

      Delete all clusters before uninstalling:
        kanata get clusters
        kanata delete cluster <name>   # repeat for each cluster

      Then:
        brew uninstall mazrean/tap/kanata
    EOS
  end

  test do
    assert_path_exists bin/"kanata"
    assert_path_exists share/"kanata/vm.entitlements"
    assert_path_exists share/"kanata/kernel/vmlinux"
    assert_path_exists share/"kanata/nat-kernel/vmlinux"
  end
end
