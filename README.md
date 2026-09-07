# Ubuntu Server Script Suite

A modular, rerunnable Bash toolkit for bootstrapping and maintaining Ubuntu
servers, including Ubuntu instances hosted in Oracle Cloud.

## Supported systems

- Ubuntu 22.04 LTS, 24.04 LTS, or 26.04 LTS
- A normal login user with interactive `sudo` access
- Internet access for package installation
- Bash

Run the scripts as the normal login user, not as `root`. The Docker setup adds
that user to the `docker` group, which grants root-equivalent access. Log out
and back in after Docker installation before running Docker without `sudo`.

## Quick start

```bash
git clone https://github.com/hitesh920/scripts.git
cd scripts
chmod +x ./*.sh ./tests/*.sh
./bootstrap.sh
```

The guided bootstrap updates Ubuntu, installs Git and Python tooling, installs
GitHub CLI and Docker from their official apt repositories, and then offers to
configure GitHub authentication and Bash aliases.

## Scripts

| Script | Purpose |
| --- | --- |
| `bootstrap.sh` | Run the complete guided installation sequence |
| `update-system.sh` | Install all Ubuntu updates and clean apt packages |
| `install-dev-tools.sh` | Install Git, Python, pip, venv, pipx, and GitHub CLI |
| `install-docker.sh` | Install Docker Engine, Buildx, and Compose |
| `setup-git.sh` | Configure Git identity and GitHub CLI HTTPS authentication |
| `setup-aliases.sh` | Install managed Git, Docker, and Compose aliases |
| `clean-server.sh` | Safely remove disposable system junk |
| `clean-docker.sh` | Choose normal Docker pruning or a complete forced wipe |
| `reset-server.sh` | Remove Docker and development configuration while preserving the server |

Every setup script is safe to rerun. Scripts reject unsupported operating
systems and unsafe root execution before making changes.

## System and development setup

Run individual setup steps when the complete bootstrap is not needed:

```bash
./update-system.sh
./install-dev-tools.sh
./install-docker.sh
./setup-git.sh
./setup-aliases.sh
```

`update-system.sh` performs an apt index update, full upgrade, unused-package
removal, and apt cache cleanup. It reports whether Ubuntu requires a reboot but
never reboots automatically.

`install-dev-tools.sh` installs Ubuntu's supported `python3`, `python3-pip`,
`python3-venv`, and `pipx` packages without replacing Ubuntu's system Python.
It installs GitHub CLI from GitHub's official repository.

`install-docker.sh` uses Docker's official stable apt repository. It removes
conflicting distribution packages, installs Docker Engine, CLI, containerd,
Buildx, and the Compose plugin, enables Docker, and adds the current user to the
`docker` group.

## Git and GitHub setup

`setup-git.sh` offers these editable defaults:

- Name: `hitesh kamble`
- Email: `hiteshkamble920@gmail.com`
- GitHub username: `hitesh920`

It authenticates with `gh auth login` using GitHub's browser/device flow and
configures HTTPS Git operations with `gh auth setup-git`. It does not ask for
or directly store a personal access token.

## Managed aliases

`setup-aliases.sh` replaces only blocks marked as managed by this repository.
Existing content elsewhere in `~/.bash_aliases` and `~/.bashrc` is preserved.

| Area | Aliases |
| --- | --- |
| Git | `g`, `gs`, `ga`, `gaa`, `gc`, `gcm`, `gp`, `gpl`, `gl`, `gco`, `gb` |
| Docker | `d`, `dps`, `dpsa`, `di`, `dex`, `dl` |
| Compose | `dc`, `dcu`, `dcd`, `dcl`, `dcp`, `dcb` |

Activate the aliases after installation:

```bash
source ~/.bashrc
```

## Safe server cleanup

Preview the cleanup first:

```bash
./clean-server.sh --dry-run
```

Run it after reviewing the preview:

```bash
./clean-server.sh
```

The safe cleanup removes:

- unused apt packages and apt caches
- disabled Snap revisions
- files in `/var/crash`
- temporary files eligible under the server's systemd-tmpfiles policies
- system journal entries older than 14 days

It does **not** remove user files or configuration, projects, SSH keys, network
or firewall configuration, cloud agents, installed applications, or Docker
data.

## Docker cleanup

Preview either Docker mode without deleting anything:

```bash
./clean-docker.sh --dry-run
```

The interactive menu provides:

1. **Normal cleanup:** removes stopped containers, images not used by a
   container, unused volumes, unused local custom networks, and build cache.
   Running containers remain untouched.
2. **Force cleanup:** removes every standalone container, including running
   containers, followed by every image, volume, local custom network, and build
   cache. It requires typing `DELETE ALL DOCKER DATA` exactly.
3. **Cancel:** exits without changes.

Both modes affect only the current Docker context. Swarm stacks, services,
secrets, configs, plugins, built-in networks, and other contexts are not
targeted.

## Full development reset

Always preview a reset first:

```bash
./reset-server.sh --dry-run
```

Run the live reset only after reviewing every target:

```bash
./reset-server.sh
```

The live reset requires typing `RESET DEVELOPMENT STATE` exactly. It stops and
purges Docker/containerd, removes Docker data and installation traces, removes
the current user's Git/GitHub authentication and global Git configuration, and
removes aliases managed by this suite. It then performs the safe server
cleanup. A reboot is offered only after every cleanup stage succeeds.

The reset preserves:

- every personal file and project under the user's home directory
- `.ssh` and all project `.git` directories
- installed Git, Python, pipx, and GitHub CLI packages
- users, networking, firewall rules, SSH service, and cloud agents

This is a development-environment reset, not an operating-system factory
reset. Reprovision the instance when a pristine operating system is required.

## Validation

Run syntax checks and the mocked safety tests:

```bash
bash -n ./*.sh ./lib/*.sh ./tests/*.sh
bash ./tests/run-tests.sh
```

Install ShellCheck and run linting:

```bash
sudo apt-get update
sudo apt-get install -y shellcheck
shellcheck ./*.sh ./lib/*.sh ./tests/*.sh
```

The mocked tests verify Ubuntu rejection, alias idempotency and preservation,
Docker normal/force/cancel behavior, confirmation guards, and zero-mutation dry
runs. GitHub Actions runs the syntax, ShellCheck, and mocked test suite on every
push and pull request.

Destructive integration testing should be performed only on a disposable
Ubuntu VM. Verify a fresh and repeated bootstrap, GitHub authentication,
Docker's `hello-world`, both Docker cleanup modes, SSH reconnection after a full
reset, and preservation of test projects.

## Upstream installation references

- [Install Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [Install GitHub CLI on Linux](https://github.com/cli/cli/blob/trunk/docs/install_linux.md)
- [Authenticate with GitHub CLI](https://cli.github.com/manual/gh_auth_login)
