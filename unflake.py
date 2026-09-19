#!/usr/bin/env python3

# unflake - break free of the flakes tyranny
# Copyright (C) 2025 Maximilian Siling, unflake contributors
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3
# as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

VERSION = '0.2'
USER_AGENT = f'unflake/{VERSION} (contact: goldstein@tty5.dev)'

import re
import os
import sys
import json
import time
import shlex
import getopt
import typing
import asyncio
import functools
import subprocess
import http.client
import urllib.error
import urllib.parse
import urllib.request
from enum import Enum
from typing import Any, Self, TypeAlias, Literal, assert_never
from pathlib import Path
from dataclasses import dataclass
from collections.abc import Callable, Coroutine, Iterable, Awaitable


# this morally belongs to data model, but is used in main, so

# types collected by basically looking at all the attrs
# we can't use the new `type` syntax because it doesn't work with `isinstance()` for some reason
FlakeRefValue: TypeAlias = str | int | bool
FlakeRef: TypeAlias = dict[str, FlakeRefValue]
# flakeref, but sanitized and sorted
StableFlakeRef: TypeAlias = tuple[tuple[str, FlakeRefValue], ...]

# === main === {{{

# handled as a global because we don't want to manually pass config to logging
# meaning:
# -2: don't print anything
# -1: print section headers
#  0: print section timings, allow subprocess stderrs
# +1: print commands & other minute actions
VERBOSITY = 0

# also a global, used in `sh()` function for every spawned command
SHELLOUT_SEMAPHORE = asyncio.Semaphore(4)

@dataclass
class Arguments:
    inputs_nix: str | None = None
    output_file: str = "unflake.nix"
    backend: Literal["npins", "nix"] | None = None
    flake_mode: Literal["convert", "use"] | None = None
    update: set[str] | None = None

def usage() -> None:  # pragma: no cover
    log("usage: unflake [options]")
    log("")
    log("options:")
    log("  (-i | --inputs=) <file>           path to `inputs.nix` file")
    log("  (-o | --output=) <file>           path to output `unflake.nix` file")
    log("  (-b | --backend=) (npins|nix)     use specified backend")
    log("                                    default is `npins` if `npins/` exists, `nix` otherwise")
    log("  (-f | --flake)                    use `flake.nix` instead of `inputs.nix`")
    log("  (-u | --update=) (name|flakeref)  only update specified input")
    log("                                    can be passed multiple times")
    log("  --convert-flake                   convert `flake.nix` into `inputs.nix` first")
    log("  (-j | --jobs=) <count>            max amount of processes to spawn, defaults to 4")
    log("                                    you could set this to 0 for $(nproc),")
    log("                                    but unflake isn't CPU-bound, so it likely won't help")
    log("  -q | --quiet                      reduce output verbosity")
    log("  -v | --verbose                    increase output verbosity")
    log("  --help                            show this help and exit")
    log("  --version                         show version info and exit")

async def run(args: Arguments) -> None:
    started = time.monotonic()

    # we have no inputs but we must run: use `flake.nix` then
    if (
        args.flake_mode is None
        and args.inputs_nix is None
        and not Path("inputs.nix").is_file()
        and Path("flake.nix").is_file()
    ):
        args.flake_mode = "use"

    match args.flake_mode:
        case "use":
            inputs_kind = InputsKind.FlakeNix
            inputs = args.inputs_nix or "flake.nix"
        case "convert" | None:
            inputs_kind = InputsKind.InputsNix
            inputs = args.inputs_nix or "inputs.nix"
        case other_mode:  # pragma: no cover
            # assert match is exhaustive
            assert_never(other_mode)

    if args.flake_mode == "convert":
        with LogSection(f"converting `flake.nix` to `{inputs}`..."):
            await convert_flake_nix(inputs)

    with LogSection(f"reading `{inputs}`..."):
        inputs_nix = await read_nix_inputs(Path(inputs), inputs_kind)
        config, base_deps, base_follows = await parse_inputs_nix(inputs_nix)
        updates = await parse_update_set(args.update, base_deps) if args.update is not None else None

    ctx = Context(args=args, config=config, updates=updates)
    with LogSection("resolving flake dependencies..."):
        resolved = await resolve(ctx, base_deps, base_follows)

    backend = args.backend
    if backend is None:
        if Path("npins").is_dir():
            backend = "npins"
        else:
            backend = "nix"

    match backend:
        case 'npins':
            await npins_backend(ctx, resolved, args.output_file)
        case 'nix':
            await bare_nix_backend(ctx, resolved, args.output_file)
        case other_backend:  # pragma: no cover
            # assert match is exhaustive
            assert_never(other_backend)

    elapsed = format_time(time.monotonic() - started)
    if elapsed is not None:
        LogSection(f"finished in {elapsed}!")
    else:  # pragma: no cover
        LogSection("done!")

def parse_args(args: list[str]) -> Arguments:
    global VERBOSITY
    global SHELLOUT_SEMAPHORE

    try:
        opts, args = getopt.gnu_getopt(
            args, "qvj:i:o:b:fu:",
            ["help", "version", "quiet", "verbose", "jobs=", "inputs=", "output=", "backend=", "flake", "convert-flake", "update="]
        )
    except getopt.GetoptError as err:  # pragma: no cover
        log(f"failed to parse arguments: {err}\n")
        usage()
        sys.exit(2)
    if args:  # pragma: no cover
        log("unflake doesn't take positional arguments\n")
        usage()
        sys.exit(2)
    result = Arguments()
    update: set[str] = set()

    for opt, arg in opts:
        match opt:
            case '--help':  # pragma: no cover
                usage()
                sys.exit(0)
            case '--version':  # pragma: no cover
                log(f"unflake v{VERSION}")
                sys.exit(0)
            case ('-q' | '--quiet'):  # pragma: no cover
                VERBOSITY -= 1
            case ('-v' | '--verbose'):  # pragma: no cover
                VERBOSITY += 1
            case ('-j' | '--jobs'):  # pragma: no cover
                if not arg.isdigit():
                    log(f"{opt} argument must be a non-negative integer")
                    usage()
                    sys.exit(2)
                # safe to override here, we're not yet running anything async
                if int(arg) == 0:
                    SHELLOUT_SEMAPHORE = asyncio.Semaphore(len(os.sched_getaffinity(0)))
                else:
                    SHELLOUT_SEMAPHORE = asyncio.Semaphore(int(arg))
            case ('-i' | '--inputs'):
                result.inputs_nix = arg
            case ('-o' | '--output'):
                result.output_file = arg
            case ('-b' | '--backend'):
                if arg not in ('npins', 'nix'):  # pragma: no cover
                    log("backend must be either `npins` or `nix`")
                    usage()
                    sys.exit(2)
                # mypy can't infer this for some reason
                result.backend = typing.cast(Literal["npins", "nix"], arg)
            case ('-f' | '--flake'):
                if result.flake_mode not in ("use", None):  # pragma: no cover
                    log("both `--convert-flake` and `--flake` are specified")
                    sys.exit(2)
                result.flake_mode = "use"
            case ('-u' | '--update'):
                update.add(arg)
            case '--convert-flake':
                if result.flake_mode not in ("convert", None):  # pragma: no cover
                    log("both `--convert-flake` and `--flake` are specified")
                    sys.exit(2)
                result.flake_mode = "convert"

    if update:
        result.update = update

    return result

async def convert_flake_nix(inputs_nix: str) -> None:
    output = await sh('nix-instantiate', '--eval', '--strict', '--attr', 'inputs', 'flake.nix')
    with open(inputs_nix, 'w') as fp:
        fp.write(output)

def main(raw_args: list[str] | None = None) -> None:
    if raw_args is None:  # pragma: no cover
        raw_args = sys.argv[1:]

    # enable features we use so the user doesn't have to
    os.environ['NIX_CONFIG'] = (
        (os.environ['NIX_CONFIG'] + "\n" if 'NIX_CONFIG' in os.environ else '')
        # it's ok to have duplicate `extra-experimental-features` on both cppnix and lix
        + 'extra-experimental-features = nix-command flakes'
    )

    args = parse_args(raw_args)
    try:
        asyncio.run(run(args))
    # TODO: parse backtrace to show better path to error ig
    except* AssertionError as eg:  # pragma: no cover
        log_exceptions(eg, str)
    except* subprocess.CalledProcessError as eg:  # pragma: no cover
        log_exceptions(eg, format_cmd_error)
    except* urllib.error.HTTPError as eg:
        log_exceptions(eg, format_http_error)
    except* OSError as eg:  # pragma: no cover
        log_exceptions(eg, str)
    else:
        sys.exit(0)
    sys.exit(1)  # pragma: no cover

# }}}

# === data model === {{{

# magic value for the root "flake" we're working with
# can't occur naturally, since it doesn't have a type
ROOT: StableFlakeRef = ()

# allowed fields for various flakeref types
# some types erroneously (?) allow `rev` and `revCount`, which i filtered out
# the order of the fields is the order in serialized input name
# for that purpose, first tuple specifies positional fields and the second specifies kw fields
FLAKEREF_FIELDS: dict[str, tuple[tuple[str, ...], tuple[str, ...]]] = {
    # https://git.lix.systems/lix-project/lix/src/commit/b966d2e53bd6f5f03ae86b60b12d7489cf91f1a6/lix/libfetchers/indirect.cc#L11
    "indirect": (("type", "id"), ("ref", "rev")),
    # https://git.lix.systems/lix-project/lix/src/commit/b966d2e53bd6f5f03ae86b60b12d7489cf91f1a6/lix/libfetchers/path.cc#L14
    "path": (("type", "path"), ()),
    # https://git.lix.systems/lix-project/lix/src/commit/b966d2e53bd6f5f03ae86b60b12d7489cf91f1a6/lix/libfetchers/git.cc#L320
    # i only list the attrs i understand, feel free to send an issue/PR if something useful is missing
    "git": (("type", "url"), ("ref", "rev", "revCount", "shallow", "submodules", "allRefs")),
    # https://git.lix.systems/lix-project/lix/src/commit/b966d2e53bd6f5f03ae86b60b12d7489cf91f1a6/lix/libfetchers/github.cc#L26
    "github": (("type", "owner", "repo"), ("ref", "rev", "host")),
    "gitlab": (("type", "owner", "repo"), ("ref", "rev", "host")),
    "sourcehut": (("type", "owner", "repo"), ("ref", "rev", "host")),
    # https://git.lix.systems/lix-project/lix/src/commit/b966d2e53bd6f5f03ae86b60b12d7489cf91f1a6/lix/libfetchers/mercurial.cc#L50
    "hg": (("type", "url"), ("ref", "rev", "revCount")),
    # https://git.lix.systems/lix-project/lix/src/commit/b966d2e53bd6f5f03ae86b60b12d7489cf91f1a6/lix/libfetchers/tarball.cc#L234
    # unpack doesn't appear to be doing anything and is silently stripped by cppnix
    "tarball": (("type", "url"), ("rev", "revCount")),
    "file": (("type", "url"), ("rev", "revCount")),
}

# fields returned by `fetchTree` and used for pinning
# see: https://git.lix.systems/lix-project/lix/issues/52#issuecomment-15737
# lumped there together, we'll copy everything we've got
FLAKEREF_PIN_FIELDS = ("revCount", "lastModified", "narHash")

@dataclass(kw_only=True, frozen=True)
class InputSpec:
    fields: StableFlakeRef
    flake: bool

    def sort_key(self) -> tuple[object, ...]:
        # 'fields' is already a sorted tuple of tuples, so it sorts deterministically
        return (self.fields, self.flake)

    @functools.cache
    def type(self) -> str:
        attrs = dict(self.fields)
        assert isinstance(attrs["type"], str), f"type is not a string in flake ref {self}"
        return attrs["type"]

    @functools.cache
    def dir(self) -> str | None:
        attrs = dict(self.fields)
        if "dir" in attrs:
            assert isinstance(attrs["dir"], str), f"dir is not a string in flake ref {self}"
            return attrs["dir"]
        return None

    def is_indirect(self) -> bool:
        return self.type() == "indirect"

    @classmethod
    def root(cls) -> Self:
        return cls(fields=ROOT, flake=False)

    # this spec, but with `dir` and `flake` reset
    def canonical(self) -> Self:
        return type(self)(fields=self.fields, flake=True)

    @classmethod
    def from_attrs(cls, attrs: FlakeRef, *, flake: bool) -> Self:
        if attrs["type"] in ("github", "gitlab"):
            # case-insensitive in owner/repo
            if "owner" in attrs:
                owner = attrs["owner"]
                assert isinstance(owner, str), f".owner is not a string in flakeref: {attrs}"
                attrs["owner"] = owner.lower()
            if "repo" in attrs:
                repo = attrs["repo"]
                assert isinstance(repo, str), f".repo is not a string in flakeref: {attrs}"
                attrs["repo"] = repo.lower()

        if "dir" in attrs:
            assert isinstance(attrs["dir"], str), f".dir must be string if present in flakeref: {attrs}"

        attrs = sanitize_flakeref(attrs)
        return cls(fields=tuple(sorted(attrs.items())), flake=flake)

    @functools.cache
    def stable_id(self) -> str:
        sanitize = lambda val: re.sub(r"[^a-zA-Z0-9_-]", "-", val)  # type: Callable[[str], str]

        attrs = dict(self.fields)
        assert attrs["type"] in FLAKEREF_FIELDS, f"flakeref has unknown type {attrs["type"]}"
        assert isinstance(attrs["type"], str)  # redundant, mypy needs it
        pos, kw = FLAKEREF_FIELDS[attrs["type"]]
        parts = ["unflake"]

        for key in pos:
            assert key in attrs, f"flakeref is missing required field `{key}`: {attrs}"
            parts.append(sanitize(str(attrs[key])))

        for key in kw:
            if key in attrs:
                val = attrs[key]
                match val:
                    case str():
                        parts += [key, sanitize(val)]
                    # bool must be before int because bool <: int, fun
                    case bool():
                        if val:
                            parts.append(key)
                    case int():
                        parts += [key, str(val)]
                    case _ as other:  # pragma: no cover
                        # assert match is exhaustive
                        assert_never(other)

        if not self.flake:
            parts += ["flake", "false"]

        dir = self.dir()
        if dir is not None:
            parts += ["dir", sanitize(dir)]

        return "_".join(parts)

# }}}

# === config === {{{

@dataclass(kw_only=True)
class DedupRule:
    when: dict[str, FlakeRefValue | None]
    set: dict[str, FlakeRefValue | None] | None
    replace: dict[str, FlakeRefValue] | str | None

@dataclass(kw_only=True)
class Config:
    dedup_rules: list[DedupRule]

# holds info about the run
# doesn't hold anything produced past parsing
@dataclass(kw_only=True)
class Context:
    args: Arguments
    config: Config
    updates: set[StableFlakeRef] | None

    # for compatibility with caching, contexts are hashed to their IDs and equal iff identical
    def __eq__(self, other: object) -> bool:
        return self is other

    def __hash__(self) -> int:
        return id(self)

# *sigh*
@functools.cache
def nix_flavor() -> Literal['cppnix', 'lix']:  # pragma: no cover
    res = subprocess.run(('nix-instantiate', '--version'), stdout=subprocess.PIPE, encoding='utf-8', check=True)
    assert res.stdout is not None
    if 'Lix' in res.stdout:
        return 'lix'
    if '(Nix)' in res.stdout:
        return 'cppnix'
    raise AssertionError(f'running on unknown Nix implementation: {res.stdout}')

# https://git.lix.systems/lix-project/lix/src/commit/43b1b63df98635d90a489695548294567c40e5a6/lix/libstore/globals.cc#L64
@functools.cache
def nix_conf_dir() -> Path:
    return Path(os.environ.get("NIX_CONF_DIR", "/etc/nix"))

@functools.cache
def nix_user_conf_dir() -> Path:
    # this one is cppnix-specific:
    # https://github.com/NixOS/nix/blob/a6eb2e91b70c3ad874c494fe169a498dc432dd44/src/libutil/users.cc#L25
    if 'NIX_CONFIG_HOME' in os.environ:
        return Path(os.environ['NIX_CONFIG_HOME'])
    # these ones are also supported by lix:
    # https://git.lix.systems/lix-project/lix/src/commit/43b1b63df98635d90a489695548294567c40e5a6/lix/libutil/users.cc#L97-L101
    if 'XDG_CONFIG_HOME' in os.environ:
        return Path(os.environ['XDG_CONFIG_HOME']) / 'nix'
    return Path.home() / '.config' / 'nix'

@functools.cache
def cache_dir() -> Path:
    if 'XDG_CACHE_HOME' in os.environ:
        path = Path(os.environ['XDG_CACHE_HOME']) / 'unflake'
    else:
        path = Path.home() / '.cache' / 'unflake'
    path.mkdir(parents=True, exist_ok=True)
    return path 

# }}}

# === asyncio utils === {{{

# run a command and return stdout, checking return code
async def sh(*command: str) -> str:
    async with SHELLOUT_SEMAPHORE:
        log_command(command)
        proc = await asyncio.create_subprocess_exec(
            *command,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE if VERBOSITY < 0 else None,
        )

        stdout, stderr = await proc.communicate()
        returncode = await proc.wait()
    if returncode != 0:  # pragma: no cover
        raise subprocess.CalledProcessError(returncode, command, stderr=stderr)

    return stdout.decode('utf-8')

# `Any` is in the actual type inferred for async fns
def async_cache[**A, R](func: Callable[A, Awaitable[R]]) -> Callable[A, Coroutine[Any, Any, R]]:
    @dataclass
    class Entry:
        value: R | None = None
        event: asyncio.Event | None = None

    cache: dict[object, Entry] = dict()

    @functools.wraps(func)
    async def inner(*args: A.args, **kwargs: A.kwargs) -> R:
        assert not kwargs, "bug: @async_cache used with keyword arguments"
        while True:
            if args not in cache:
                cache[args] = Entry()
            entry = cache[args]
            if entry.value is not None:
                return entry.value
            elif entry.event is not None:
                await entry.event.wait()
            else:
                entry.event = asyncio.Event()
                try:
                    # this `type: ignore` is for pyright, mypy is ok
                    entry.value = await func(*args, **kwargs)  # type: ignore
                    return entry.value
                finally:
                    event, entry.event = entry.event, None
                    event.set()

    return inner  # type: ignore

# }}}

# === resolver === {{{

@dataclass
class Resolved:
    # flat set of all (possibly transitive) dependencies
    all_deps: set[InputSpec]
    # dep -> alias -> its deps
    injections: dict[InputSpec, dict[str, InputSpec]]

# tries to resolve `flakeref` from an existing `unflake.nix` file
# returns None if:
# - this flakeref is supposed to be updated, i.e.
#   - either `--update` was not passed,
#   - or this flakeref is in the updates list.
# - or if this flakeref is not in the lockfile
@async_cache
async def fetch_tree_cached(
        ctx: Context, flakeref: StableFlakeRef
) -> tuple[dict[str, object] | None, FlakeRef | None]:
    if ctx.updates is None or flakeref in ctx.updates:
        return None, None
    
    unflake_nix = Path(ctx.args.output_file)
    assert Path(ctx.args.output_file).is_file(), f"tried to use `--update` while `{ctx.args.output_file}` does not exist"
    spec = InputSpec.from_attrs(dict(flakeref), flake=True).canonical()
    name = spec.stable_id()
    tree_json = await sh(
        'nix-instantiate', '--eval', '--json', '--strict', '--expr',
        '--argstr', 'unflake_nix', str(unflake_nix.absolute()),
        '--argstr', 'name', name,
        # this returns null if `unflake.nix` is too old to support partial updates
        # serialization to JSON is magical wrt `.outPath`, so we need to hide it first, similar to `fetch_tree`
        '{ name, unflake_nix }: let u = import unflake_nix; d = u._unflake.deps or null; in ' # <- no comma
        'if d == null then "unsupported" else ' # <- still no comma
        'if !d?${name} then null else ' # <- yeah, still no comma
        '[d.${name}.outPath (builtins.removeAttrs d.${name} ["outPath"]) (u._unflake.specs.${name} or null)]',
    )
    maybe_tree = json.loads(tree_json)
    assert maybe_tree != "unsupported", "tried to use `--update`, but `unflake.nix` is too old to be compatible with partial updates"
    if maybe_tree is None:
        return None, None

    outpath, res, locked_flakeref = maybe_tree
    assert isinstance(res, dict), f"builtins.fetchTree returned non-attrs: {res}"
    res['outPath'] = outpath

    cached_flakeref = None
    if locked_flakeref is not None:
        assert isinstance(locked_flakeref, dict), f"stored flakeref in unflake.nix is not attrs: {locked_flakeref}"
        cached_flakeref = sanitize_flakeref(verify_flakeref(locked_flakeref))

    return res, cached_flakeref

def link_rel_immutable(headers: typing.Iterable[tuple[str, str]]) -> str | None:
    for name, value in headers:
        # undocumented feature: x-amz-meta-link is also supported
        # https://git.lix.systems/lix-project/lix/src/commit/0f3a66f856fd33c575984ee5ee5b5a03aa0f19fb/lix/libstore/filetransfer.cc#L377
        if name.lower() not in ('link', 'x-amz-meta-link'):
            continue
        m = re.match(r'\s*<([^>]+)>;.*\srel="?immutable"?(?:;|\s*$).*', value)
        if m is not None:
            return m[1]
    return None

@functools.cache
def lockable_tarballs_http_opener() -> urllib.request.OpenerDirector:
    r = urllib.request

    class RedirectHandler(r.HTTPRedirectHandler):
        def redirect_request(self,
            req: urllib.request.Request, fp: typing.IO[bytes], code: int, msg: str, headers: http.client.HTTPMessage, newurl: str
        ) -> urllib.request.Request | None:
            if link_rel_immutable(headers.items()) is not None:
                return None
            return super().redirect_request(req, fp, code, msg, headers, newurl)

    return r.build_opener(
        r.UnknownHandler(),
        r.HTTPHandler(), r.HTTPDefaultErrorHandler(), RedirectHandler(),
        r.FTPHandler(), r.FileHandler(), r.HTTPErrorProcessor(),
    )

# TODO: there's no async HTTP library in std
# we could either do raw HTTP (painful) or shell out to curl (requires curl)
# or do some combination (shell out to curl if present, else use urllib?)
@async_cache
async def resolve_lockable_tarball(url: str, is_flake: bool) -> FlakeRef | None:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme.lower() not in ('http', 'https'):
        # we only support resolving links for HTTP URLs
        return None

    request = urllib.request.Request(url, method='HEAD')
    request.add_header('User-Agent', USER_AGENT)
    if VERBOSITY > 0:  # pragma: no cover
        log(f"- fetching {url}...")
    # we know it's HTTP, because we checked the scheme
    try:
        response = typing.cast(http.client.HTTPResponse, lockable_tarballs_http_opener().open(request))
        new_url = link_rel_immutable(response.headers.items())
    except urllib.error.HTTPError as err:
        # got served a redirect, but it has rel=immutable
        if 300 <= err.code < 400:
            new_url = link_rel_immutable(err.headers.items())
        else:
            raise

    if new_url is not None:
        return await parse_flakeref(new_url, is_flake)
    return None

# the second return is the locked flakeref
@async_cache
async def fetch_tree(ctx: Context, spec: StableFlakeRef, is_flake: bool) -> tuple[dict[str, object], FlakeRef]:
    flakeref = dict(spec)

    cached, cached_flakeref = await fetch_tree_cached(ctx, spec)
    if cached is not None:
        return cached, cached_flakeref or flakeref

    # possible switcheroo: lockable tarballs
    # our `unflake.nix` is morally a lockfile, so we need to support it
    if flakeref.get("type") in ("tarball", "file"):
        url = flakeref.get("url")
        assert isinstance(url, str), f"URL is not a string in flakeref: {flakeref}"
        immutable_flakeref = await resolve_lockable_tarball(url, is_flake)
        if immutable_flakeref is not None:
            flakeref = immutable_flakeref

    locked_flakeref = dict(flakeref)
    flakeref.pop("dir", None)  # not relevant for fetching
 
    # we avoid serializing to nixlang by doing a brilliant move and reading from json
    flakeref_json = json.dumps(flakeref)
    tree_json = await sh(
        'nix-instantiate', '--eval', '--json', '--strict', '--expr', '--argstr', 'ref', flakeref_json,
        # serialization to JSON is magical wrt `.outPath`, so we need to hide it first
        '{ ref }: let t = builtins.fetchTree (builtins.fromJSON ref); in [t.outPath (builtins.removeAttrs t ["outPath"])]',
    )
    outpath, res = json.loads(tree_json)
    assert isinstance(res, dict), f"builtins.fetchTree returned non-dict: {res}"
    res['outPath'] = outpath
    return res, locked_flakeref

@async_cache
async def fetch_flake_nix(ctx: Context, spec: InputSpec) -> Path:
    # resolve from system registry manually, since cppnix would ignore it:
    # https://github.com/NixOS/nix/blob/a6eb2e91b70c3ad874c494fe169a498dc432dd44/src/libexpr/primops/fetchTree.cc#L198
    # https://github.com/NixOS/nix/blob/a6eb2e91b70c3ad874c494fe169a498dc432dd44/src/libfetchers/registry.cc#L191-L194
    if spec.is_indirect():
        spec = apply_flake_registry(system_flake_registry(), spec) or spec

    dir = spec.dir() or '.'

    tree, _ = await fetch_tree(ctx, spec.fields, spec.flake)
    root_path = tree.get('outPath')
    assert isinstance(root_path, str), f"builtins.fetchTree returned non-string in `outPath`: {root_path}"

    return Path(root_path) / dir / "flake.nix"

async def dedup_deps(config: Config, deps: dict[str, InputSpec]) -> dict[str, InputSpec]:
    result = dict()

    for name, spec in deps.items():
        if spec.is_indirect():
            # if there's no match in system registry
            if apply_flake_registry(system_flake_registry(), spec) is None:
                # try to resolve through global registry
                resolved = apply_flake_registry(global_flake_registry(), spec)
                assert resolved is not None, f"failed to find {spec} in flake registries"
                spec = resolved

        attrs = dict(spec.fields)

        for rule in config.dedup_rules:
            for key, condition in rule.when.items():
                if attrs.get(key) != condition:
                    break
            else:
                if rule.set is not None:
                    for key, value in rule.set.items():
                        if value is None:
                            attrs.pop(key, None)
                        else:
                            attrs[key] = value
                else:
                    assert rule.replace is not None, f"bug: dedup rule {rule} has neither .set nor .replace"
                    if isinstance(rule.replace, str):
                        attrs = await parse_flakeref(rule.replace, spec.flake)
                    else:
                        attrs = rule.replace
        result[name] = InputSpec.from_attrs(attrs, flake=spec.flake)

    return result

async def resolve(ctx: Context, base_deps: dict[str, InputSpec], base_follows: dict[str, tuple[str, ...]]) -> Resolved:
    base_deps = await dedup_deps(ctx.config, base_deps)
    all_deps = set(base_deps.values())
    injections = { InputSpec.root(): base_deps }

    # all the specs we ever encountered
    known = set(all_deps)
    # mapping (path to input) -> InputSpec
    paths: dict[tuple[str, ...], InputSpec] = { (): InputSpec.root() }
    # mapping path to input -> alias -> path to dependency
    follows: dict[tuple[str, ...], dict[str, tuple[str, ...]]] = { (): base_follows }

    # as opposed to some other concurrent algorithms in this program,
    # this implicitly stores return values at their proper places
    # instead of returning them and then collecting.
    # it's a bit less pretty conceptually, but much nicer in code.
    async def solve_one(tg: asyncio.TaskGroup, curr: InputSpec, path: tuple[str, ...]) -> None:
        flake_nix_path = await fetch_flake_nix(ctx, curr)
        inputs = await read_nix_inputs(flake_nix_path, InputsKind.FlakeNix)
        curr_deps, curr_follows = await parse_inputs(inputs, path)
        follows.setdefault(path, dict()).update(curr_follows)
        curr_deps = await dedup_deps(ctx.config, curr_deps)
        all_deps.update(curr_deps.values())
        for alias, dep in curr_deps.items():
            paths[path + (alias,)] = dep
            if dep not in known:
                known.add(dep)
                if dep.flake:
                    tg.create_task(solve_one(tg, dep, path + (alias,)))
        injections[curr] = curr_deps

    async with asyncio.TaskGroup() as tg:
        for alias, dep in base_deps.items():
            paths[(alias,)] = dep
            if dep.flake:
                tg.create_task(solve_one(tg, dep, (alias,)))

    # safe to proceed, because all the tasks (including child tasks) finished
    # re-inject all .follows
    while follows:
        remaining_follows: dict[tuple[str, ...], dict[str, tuple[str, ...]]] = dict()
        for path, follows_map in follows.items():
            for alias, dep_path in follows_map.items():
                assert path in paths, f"bug: found .follows for unknown path {path}"
                base_dep_path, dep_alias = dep_path[:-1], dep_path[-1]
                if base_dep_path in paths and dep_alias in injections.get(paths[base_dep_path], dict()):
                    paths[path + (alias,)] = injections[paths[path]][alias] = injections[paths[base_dep_path]][dep_alias]
                else:
                    remaining_follows.setdefault(path, dict())[alias] = dep_path
        assert follows != remaining_follows, (
            f"stuck while resolving .follows:\n"
            + "\n".join(
                f"{"/".join(path + (alias,))} follows {"/".join(dep_path)}"
                for path, follows_map in follows.items()
                for alias, dep_path in follows_map.items()
            )
        )
        follows = remaining_follows

    return Resolved(all_deps, injections)

# }}}

# === flake registries === {{{

@dataclass(kw_only=True)
class FlakeRegistryEntry:
    from_: FlakeRef
    to: FlakeRef
    exact: bool

type FlakeRegistry = list[FlakeRegistryEntry]

def read_flake_registry(path: Path) -> FlakeRegistry:
    with open(path) as registry_file:
        registry = json.load(registry_file)
    # v1 is not supported even by cppnix:
    # https://github.com/NixOS/nix/blob/a6eb2e91b70c3ad874c494fe169a498dc432dd44/src/libfetchers/registry.cc#L28
    assert registry.get("version") == 2, f"unknown flake registry version: {registry.get("version")}"
    flakes = registry.get("flakes", [])
    assert isinstance(flakes, list), f"flake registry contains non-list at .flakes: {flakes}"

    rules: list[FlakeRegistryEntry] = []
    for idx, rule in enumerate(flakes):
        from_ = rule.get("from")
        assert isinstance(from_, dict), f"flake registry {path}: .flakes.{idx}.from is not an object"
        to = rule.get("to")
        assert isinstance(to, dict), f"flake registry {path}: .flakes.{idx}.to is not an object"
        exact = rule.get("exact", False)
        assert isinstance(exact, bool), f"flake registry {path}: .flakes.{idx}.exact is not a bool"
        rules.append(FlakeRegistryEntry(from_=from_, to=to, exact=exact))
    return rules

@functools.cache
def configured_global_registry() -> Path | None:
    res = subprocess.run(
        ('nix', 'config', 'show', 'flake-registry'),
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    if res.returncode != 0:  # pragma: no cover
        return None
    result = res.stdout.strip()
    if result == b"vendored" and nix_flavor() == "lix":
        return None
    if result.lower().startswith(b"http:") or result.lower().startswith(b"https:"):
        return None
    return Path(result.decode())

@functools.cache
def global_flake_registry() -> FlakeRegistry:
    if (path := configured_global_registry()) is not None:
        return read_flake_registry(path)

    path = cache_dir() / "flake-registry.json"
    if not path.exists():
        url = "https://channels.nixos.org/flake-registry.json"
        if VERBOSITY > 0:
            log(f"- fetching `{url}`")
        request = urllib.request.Request(url)
        request.add_header('User-Agent', USER_AGENT)
        resp = typing.cast(http.client.HTTPResponse, urllib.request.urlopen(request))
        assert resp.status == 200, f"failed to fetch `{url}`: `{resp}`"
        path.write_bytes(resp.read())
    return read_flake_registry(path)

@functools.cache
def system_flake_registry() -> FlakeRegistry:
    rules = []
    user_registry = nix_user_conf_dir() / "registry.json"
    system_registry = nix_conf_dir() / "registry.json"
    if user_registry.exists():
        rules.extend(read_flake_registry(user_registry))
    if system_registry.exists():
        rules.extend(read_flake_registry(system_registry))
    return rules

def apply_flake_registry(registry: FlakeRegistry, spec: InputSpec) -> InputSpec | None:
    # adapted from https://git.lix.systems/lix-project/lix/src/commit/605de55fedb04cb54f95fed36e6fe12d8d7b9cfb/lix/libfetchers/registry.cc#L210
    # original code is avaliable under LGPL-2.1-or-later, which is compatible in case this counts as a modified work

    seen = set()
    curr = spec
    while True:
        assert curr not in seen, f"cycle detected on {curr} while resolving {spec} in flake registries"
        seen.add(curr)
        attrs = dict(curr.fields)
        new = None
        for entry in registry:
            if entry.exact:
                if entry.from_ == attrs:
                    new = dict(entry.to)
                    break
            else:
                if all(attrs.get(key) == entry.from_.get(key) for key in entry.from_):
                    new = dict(entry.to)
                    if "ref" in attrs and "ref" not in entry.from_:
                        new["ref"] = attrs["ref"]
                        if new.get("type") in ("github", "gitlab", "sourcehut"):
                            new.pop("rev", None)
                    if "rev" in attrs and "rev" not in entry.from_:
                        new["rev"] = attrs["rev"]
                        if new.get("type") in ("github", "gitlab", "sourcehut"):
                            new.pop("ref", None)
                    break
        if new is None:
            break
        else:
            old_dir = spec.dir()
            if "dir" not in new and old_dir is not None:
                new["dir"] = old_dir
            curr = InputSpec.from_attrs(attrs=new, flake=spec.flake)

    if not curr.is_indirect():
        return curr
    return None

# }}}

# === backend-generic code === {{{

# takes a list of newline-separated lines of nix code that produce bare deps attrset
# (i.e. a map from `InputSpec.stable_id()` to the downloaded input)
# produces full code for `unflake.nix`
def gen_unflake_nix(resolved: Resolved, deps_from: list[str]) -> str:
    out = [
        '# @generated by https://codeberg.org/goldstein/unflake',
        'let',
    ]
    indent = 2
    # write a line to output
    def w(s: str) -> None:
        for line in s.split('\n'):
            out.append(" " * indent + line)

    indirect_deps = sorted((dep for dep in resolved.all_deps if dep.is_indirect()), key=InputSpec.sort_key)
    w('indirect_deps = {')
    indent += 2
    for dep in indirect_deps:
        name = dep.stable_id()
        flakeref = dict(dep.fields)
        assert dep.flake, f"non-flake indirect inputs are not supported: {flakeref}"
        input_id = flakeref.get("id")
        assert isinstance(input_id, str), f"indirect input id is not a string: {flakeref}"
        ref = flakeref.get("ref")
        rev = flakeref.get("rev")
        if ref is not None:
            input_id += f"/{ref}"
        if rev is not None:
            input_id += f"/{rev}"
        if dep.dir() is not None:
            input_id += "?" + urllib.parse.urlencode({"dir": dep.dir()})
        w(f'{name} = builtins.getFlake "flake:{input_id}";')
    indent -= 2
    w('};')

    for line in deps_from:
        w(line)

    w('injections = rec {')
    indent += 2

    for spec in sorted(resolved.all_deps, key=InputSpec.sort_key):
        if not spec.flake:
            continue
        w(f'{spec.stable_id()} = {{')
        for alias, dep in sorted(resolved.injections[spec].items()):
            indent += 2
            w(f'{escape_nix_ident(alias)} = "{dep.stable_id()}";')
            indent -= 2
        w('};')

    indent -= 2
    w('};')

    w('''
inject = name: flake_path: subdir:
  let
    inputs = builtins.mapAttrs (_: dep: universe.${dep}) injections.${name} // {
      inherit self;
    };
    sourceInfo = deps.${name};
    outPath = "${sourceInfo.outPath}${subdir}";
    outputs = (import "${sourceInfo.outPath}/${flake_path}").outputs inputs;
    self = outputs // sourceInfo // {
      inherit inputs outputs outPath sourceInfo;
      _type = "flake";
      _flake = true;
    };
  in self;
'''.strip('\n'))

    w('universe = rec {')
    indent += 2

    for spec in sorted(resolved.all_deps, key=InputSpec.sort_key):
        name = spec.stable_id()
        if spec.flake:
            dir = spec.dir()
            # `getFlake` does the path thing for indirect deps
            flake_path = f"{dir}/flake.nix" if dir and not spec.is_indirect() else "flake.nix"
            flake_dir = f"/{dir}" if dir else ""
            w(f'{name} = inject "{name}" "{flake_path}" "{flake_dir}";')
        else:
            w(f'{name} = deps.{name};')

    indent -= 2
    w('};')

    w('inputs = {')
    indent += 2

    for alias, dep in sorted(resolved.injections[InputSpec.root()].items()):
        w(f'{escape_nix_ident(alias)} = universe.{dep.stable_id()};')

    indent -= 2
    w('};')

    indent -= 2
    w('''
in inputs // {
  withInputs = fn: let outputs = fn (inputs // { inherit self; }); self = outputs // {
    inherit inputs outputs;
    _type = "flake";
    outPath = builtins.toString ./.;
  }; in self;
  __functor = self: self.withInputs;
  self = throw "to use inputs.self, write `import ./unflake.nix (inputs: ...)`";
  _unflake = { inherit specs deps injections; };
}
'''.lstrip('\n'))

    return '\n'.join(out)

# }}}

# === npins backend === {{{

@dataclass
class NpinsDelta:
    keep: set[str]
    add_commands: list[tuple[str, ...]]

@dataclass
class NpinsSources:
    full: dict[str, object]
    # `unflake_` names that are already there
    existing_names: set[str]

async def npins_backend(ctx: Context, resolved: Resolved, out_file: str) -> None:
    npins_sources = read_npins_sources()
    with LogSection("calculating `npins/sources.json` changes..."):
        delta = await gen_npins_delta(resolved.all_deps, npins_sources.existing_names)
    to_purge = npins_sources.existing_names - delta.keep

    for old_name in to_purge:
        # we know pins is a dict, we checked it in `read_npins_sources()`
        del typing.cast(dict[str, object], npins_sources.full['pins'])[old_name]

    with open('npins/sources.json', 'w') as fp:
        json.dump(npins_sources.full, fp, indent=2, sort_keys=True)

    with LogSection("running `npins add` commands..."):
        for command in delta.add_commands:
            command = ('npins', 'add', *command)
            # deliberately not running this concurrently, not sure if that's supported
            await sh(*command)

    if ctx.updates is not None:
        with LogSection("running `npins update` commands..."):
            for update in ctx.updates:
                name = InputSpec.from_attrs(dict(update), flake=True).canonical().stable_id()
                if name in delta.keep:
                    await sh('npins', 'update', name)

    # one more sorting for easier diffing
    with open('npins/sources.json', 'r') as fp: 
        final_sources = json.load(fp)
    with open('npins/sources.json', 'w') as fp: 
        json.dump(final_sources, fp, indent=2, sort_keys=True)

    with LogSection(f"writing `{out_file}`..."):
        unflake_nix = gen_unflake_nix(resolved, [
            'specs = {};',
            'deps = indirect_deps // builtins.mapAttrs (_: v:',
            # fetched via git, can reuse their metadata
            '  if builtins.typeOf v.outPath == "set" then',
            '    v.outPath',
            '  else if v?revision then',
            '    { outPath = v.outPath; rev = v.revision; }',
            '  else',
            '    { outPath = v.outPath; }',
            ') (import ./npins/default.nix);',
        ])
        with open(out_file, 'w') as fp:
            fp.write(unflake_nix)

def read_npins_sources() -> NpinsSources:
    with open('npins/sources.json') as fp:
        sources = json.load(fp)

    assert isinstance(sources, dict), "`npins/sources.json` contains something that's not an object"
    version = sources.get("version")
    # the basic structure seems to be the same from version 0
    assert version is not None and version <= 8, f"unknown version in `npins/sources.json`: {version}"

    pins = sources.get('pins', dict())
    assert isinstance(pins, dict), f"`npins/sources.json` contains .pins that's not a dict: {pins}"

    existing_names = set(name for name in pins if name.startswith('unflake_'))

    return NpinsSources(sources, existing_names)

# generate either `--branch ...` or `--at ...` (or both)
async def npins_branch_or_at(flakeref: FlakeRef, url: str) -> tuple[str, ...]:
    if 'rev' in flakeref:
        assert isinstance(flakeref['rev'], str), f".rev must be a string in {flakeref}"
        # we can't specify a revision without also specifying a branch
        if 'ref' in flakeref:
            # good case: we have a valid `.ref` with our `.rev`
            assert isinstance(flakeref['ref'], str), f".ref must be a string in {flakeref}"
            assert not await is_git_tag(url, flakeref['ref']), f".rev is specified, but .ref is a tag in {flakeref}"
            branch = flakeref['ref']
        else:
            # bad case: we don't
            # use main branch as fallback, but not sure if it's correct
            # TODO: try to do something better? we could replicate what nix does:
            # https://git.lix.systems/lix-project/lix/src/commit/2c176afa7a405001dc618cbbedd6391fcd6b3421/lix/libfetchers/git.cc#L712-L725
            branch = await find_repo_main_branch(url)
        return ('--at', flakeref['rev'], '--branch', branch)
    elif 'ref' in flakeref:
        assert isinstance(flakeref['ref'], str), f".ref must be a string in {flakeref}"

        # https://codeberg.org/goldstein/unflake/issues/20
        if flakeref['ref'].startswith('refs/tags/'):
            return ('--at', flakeref['ref'][len('refs/tags/'):])

        if flakeref['ref'].startswith('refs/heads/'):
            return ('--branch', flakeref['ref'][len('refs/heads/'):])

        if await is_git_tag(url, flakeref['ref']):
            return ('--at', flakeref['ref'])
        else:
            return ('--branch', flakeref['ref'])
    else:
        return ('--branch', await find_repo_main_branch(url))

# logic for translating flakeref input spec into npin sources
async def gen_npins_command(spec: InputSpec) -> tuple[str, ...]:
    flakeref = dict(spec.fields)

    # helper for all the *git cases (except github, it's native)
    async def git_source(url: str) -> tuple[str, ...]:
        return ("git", *(await npins_branch_or_at(flakeref, url)), url)

    type_ = spec.type()

    # helper to extract str-typed attrs
    def str_attr(name: str, default: str | None = None) -> str:
        res = flakeref.get(name, default)
        assert isinstance(res, str), f"{type_} flakeref {flakeref} must have a string-typed attr {name}"
        return res

    # helper to format forge urls
    forge_url = (lambda default_host:
        f"https://{str_attr("host", default_host)}/{str_attr("owner")}/{str_attr("repo")}"
    )

    match type_:
        case "git":
            return (
                await git_source(str_attr("url"))
                + ("--submodules",) * bool(flakeref.get("submodules"))
            )
        case "gitlab":
            return (*(await git_source(f"{forge_url("gitlab.com")}.git")), "--submodules")
        case "sourcehut":
            # only git sourcehut repos are supported
            return (*(await git_source(forge_url("git.sr.ht"))), "--submodules")
        case "github":
            return (
                "github",
                *(await npins_branch_or_at(flakeref, f"{forge_url("github.com")}.git")),
                str_attr("owner"), str_attr("repo"),
            )
        case "tarball":
            return ("tarball", str_attr("url"))
        case "indirect":  # pragma: no cover
            raise AssertionError(f"bug: unhandled indirect input in `gen_npins_command()`")
        case ("path" | "hg" | "file") as kind:  # pragma: no cover
            raise AssertionError(f"{kind} inputs are not supported by npins: {flakeref}")
        case other:  # pragma: no cover
            raise AssertionError(f"unknown input type: {other} in {flakeref}")

# auto-skips all the sources that were already present in `existing`
async def gen_npins_delta(deps: Iterable[InputSpec], existing: set[str]) -> NpinsDelta:
    keep = set()

    # pyright needs explicit annotation for some reason, but mypy doesn't
    commands: list[tuple[str, asyncio.Task[tuple[str, ...]]]] = []
    async with asyncio.TaskGroup() as tg:
        for spec in deps:
            name = spec.stable_id()

            if name in existing:
                keep.add(name)
                continue

            if spec.is_indirect():
                # special, handled in the common backend
                continue

            commands.append((name, tg.create_task(gen_npins_command(spec))))

    add_commands = [
        ('--name', name, *command.result())
        for name, command in commands
    ]

    return NpinsDelta(keep, add_commands)

# }}}

# === bare nix backend === {{{

async def bare_nix_pin_deps(ctx: Context, resolved: Resolved) -> list[str]:
    deps_code = ["specs = rec {"]
    indent = 2
    w = lambda s: deps_code.append(" " * indent + s)

    # (remaining) indirect deps are special and are handled in the common backend
    canonical = { dep.canonical() for dep in resolved.all_deps if not dep.is_indirect() }
    canonical_ordered = sorted(canonical, key=InputSpec.sort_key)

    # prefetch concurrently
    async with asyncio.TaskGroup() as tg:
        for spec in canonical_ordered:
            tg.create_task(fetch_tree(ctx, spec.fields, spec.flake))

    for spec in canonical_ordered:
        name = spec.stable_id()
        flakeref = dict(spec.fields)
        tree, flakeref = await fetch_tree(ctx, spec.fields, spec.flake)
        # if locked version is the same as one of the other inputs, just emit an alias
        new_spec = InputSpec.from_attrs(flakeref, flake=spec.flake)
        if spec != new_spec and new_spec in canonical:
            w(f"{name} = {new_spec.stable_id()};")
            continue

        w(f"{name} = {{")
        indent += 2

        # we need to make it properly fixed-output
        for field in FLAKEREF_PIN_FIELDS:
            if field in tree:
                value = tree[field]
                assert isinstance(value, FlakeRefValue), f"`builtins.fetchTree` returned invalid type as `{field}`: {tree}"
                flakeref[field] = value

        # and do some more type-specific tweaks
        match flakeref["type"]:
            case "git" | "hg" | "github" | "gitlab" | "sourcehut":
                # we need to fix revision if it wasn't fixed already
                assert isinstance(tree.get("rev"), str), f"`builtins.fetchTree` returned non-string as `rev`: {tree}"
                flakeref["rev"] = typing.cast(str, tree["rev"])
                # for github-ish fetchers we then need to remove ref:
                # https://git.lix.systems/lix-project/lix/src/commit/0f3a66f856fd33c575984ee5ee5b5a03aa0f19fb/lix/libfetchers/github.cc#L153
                if flakeref["type"] in ("github", "gitlab", "sourcehut"):
                    flakeref.pop("ref", None)
            case "tarball" | "file":
                pass  # we handled lockable tarballs above, so we don't need to do anything here
            case "path":
                del flakeref["narHash"]  # hashing local inputs is probably not useful
            case other:  # pragma: no cover
                raise AssertionError(f"unknown input type: {other} in {flakeref}")

        # iterate in the canonical order: positional fields then kw fields from FLAKEREF_FIELDS,
        # then revCount, narHash and lastModified if present
        pos, kw = FLAKEREF_FIELDS[flakeref["type"]]
        ordered_keys = (
            [k for k in pos if k in flakeref]
            + [k for k in kw if k in flakeref]
            + [k for k in FLAKEREF_PIN_FIELDS if k in flakeref and k not in kw]
        )

        for key in ordered_keys:
            value = flakeref[key]
            # approximates nix syntax
            # really weird URLs or something might contain `${`, which needs to be escaped,
            # but i'll believe it when i see it
            serialized_value = json.dumps(value, ensure_ascii=False)
            w(f"{key} = {serialized_value};")


        indent -= 2
        w("};")

    for spec in sorted(set(resolved.all_deps) - canonical, key=InputSpec.sort_key):
        if spec.is_indirect():
            continue  # indirect deps are imported directly, no need to do this
        name = spec.stable_id()
        canonical_name = spec.canonical().stable_id()
        w(f"{name} = {canonical_name};")

    indent -= 2
    w("};")
    w("deps = indirect_deps // builtins.mapAttrs (_: spec: builtins.fetchTree spec) specs;")

    return deps_code

async def bare_nix_backend(ctx: Context, resolved: Resolved, out_file: str) -> None:
    with LogSection("pinning dependencies..."):
        deps_code = await bare_nix_pin_deps(ctx, resolved)

    with LogSection(f"writing `{out_file}`..."):
        unflake_nix = gen_unflake_nix(resolved, deps_code)
        with open(out_file, "w") as fp:
            fp.write(unflake_nix)

# }}}

# === git utils === {{{

@async_cache
async def is_git_tag(url: str, ref: str) -> bool:
    return (await sh('git', 'ls-remote', '--tags', url, ref)).strip() != ''

@async_cache
async def find_repo_main_branch(url: str) -> str:
    raw = await sh('git', 'ls-remote', '--symref', url, 'HEAD')
    m = re.search(r'refs/heads/([^\s]+)', raw)
    assert m is not None, f'failed to determine main branch for {url}'
    return m[1]

# }}}

# === parsing & sanitizing === {{{

class InputsKind(Enum):
    FlakeNix = 0
    InputsNix = 1

# flakerefs have more fields than `builtins.fetchTree` can eat
# this discards extra ones
def sanitize_flakeref(flakeref: FlakeRef) -> FlakeRef:
    assert "type" in flakeref, f"tried to access invalid flakeref: `{flakeref}`"
    assert isinstance(flakeref["type"], str), f"flakeref type is not a string in `{flakeref}`"
    allowed_fields = sum(FLAKEREF_FIELDS.get(flakeref["type"], ()), ("dir",))
    assert allowed_fields != (), f"unsupported flakeref type: `{flakeref["type"]}`"
    return {
        key: value
        for key, value in flakeref.items()
        if key in allowed_fields
    }

def verify_flakeref(attrs: dict[str, object]) -> FlakeRef:
    for key, value in attrs.items():
        assert isinstance(key, str), f"key `{key}` in flakeref `{attrs}` is not a string"
        assert isinstance(value, FlakeRefValue), f"value of {key} in `{attrs}` has unexpected type"
    return typing.cast(dict[str, FlakeRefValue], attrs)

@async_cache
async def parse_flakeref(flake_url: str, is_flake: bool) -> FlakeRef:
    raw_flakeref = await sh(
        'nix-instantiate', '--eval', '--json', '--expr', '--argstr', 'ref', flake_url,
        '{ ref }: builtins.parseFlakeRef ref',
    )

    flakeref = json.loads(raw_flakeref)
    assert isinstance(flakeref, dict), f"builtins.parseFlakeRef returned non-attrs: {flakeref}"

    if flakeref["type"] in ("tarball", "file"):
        url = flakeref.get("url")
        assert isinstance(url, str), f"{flakeref["type"]} flakeref url is not a string: {url}"

        # `file`/`tarball` flakeref parsing depends on whether dep is a flake,
        # but `builtins.parseFlakeRef` always assumes it is.
        # we replicate upstream logic here:
        # https://git.lix.systems/lix-project/lix/src/commit/be34bc0481c29f858f9444989851a6527c3e813c/lix/libfetchers/tarball.cc#L316-L319
        tarball_extensions = (".zip", ".tar", ".tgz", ".tar.gz", ".tar.xz", ".tar.bz2", ".tar.zst")
        if not (
                is_flake
                or any(url.endswith(ext) for ext in tarball_extensions)
                or flake_url.lstrip().startswith('tarball+')
        ):
            flakeref["type"] = "file"


        # lix polyfill: strip `rev` and `revCount` if present, they're flakeref attrs, not parts of the url
        parts = urllib.parse.urlsplit(url)
        flakeref["url"] = parts._replace(query=urllib.parse.urlencode(tuple(
            (name, value)
            for name, value in urllib.parse.parse_qsl(parts.query) 
            if name not in FLAKEREF_FIELDS[flakeref["type"]][1]
        ))).geturl()

    return verify_flakeref(flakeref)

# returns a tuple of normal deps and follows
async def parse_inputs(
        inputs: dict[str, object], path_prefix: tuple[str, ...]
) -> tuple[dict[str, InputSpec], dict[str, tuple[str, ...]]]:
    results = dict()
    follows = dict()

    async def parse_one(name: str, value: dict[str, object]) -> None:
        flake = True
        if "flake" in value:
            assert isinstance(value["flake"], bool), f".flake is not bool in input spec {value}"
            flake = value["flake"]

        if "follows" in value:
            assert isinstance(value["follows"], str), f"follows in flakeref {value} is not a string"
            follows[name] = path_prefix + tuple(value["follows"].split("/"))
            return
        elif "type" in value:
            # nice, attrs-like flakeref
            # `.inputs` is not a part of the flakeref proper, it's for overrides
            value.pop("inputs", None)
            attrs = verify_flakeref(value)
        elif "url" in value:
            assert isinstance(value["url"], str), f"URL in flakeref {value} is not a string"
            # TODO: maybe do some more validation?
            attrs = await parse_flakeref(value["url"], flake)
        else:
            # ugly implicit input
            # see https://codeberg.org/goldstein/unflake/issues/57
            value["id"] = name
            value["type"] = "indirect"
            value.pop("inputs", None)
            attrs = verify_flakeref(value)

        results[name] = InputSpec.from_attrs(attrs, flake=flake)


    async with asyncio.TaskGroup() as tg:
        for name, value in inputs.items():
            assert isinstance(value, dict), f"input spec {name} is not attrs: {value}"
            tg.create_task(parse_one(name, value))

    return results, follows

async def parse_inputs_nix(
        inputs: dict[str, object]
) -> tuple[Config, dict[str, InputSpec], dict[str, tuple[str, ...]]]:
    raw_config = inputs.pop("_unflake", dict())
    base_deps, base_follows = await parse_inputs(inputs, ())

    assert isinstance(raw_config, dict), "._unflake in inputs.nix is not an attrset"
    for key in raw_config:
        assert key == "dedupRules", f"`{key}` is not a valid config key"

    # a bit of gnarly parsing :(
    # if only we had serde in stdlib...
    dedup_rules = []
    if "dedupRules" in raw_config:
        raw_dedup_rules = raw_config["dedupRules"]
        assert isinstance(raw_dedup_rules, list), "._unflake.dedup_rules must be a list"
        for idx, raw_rule in enumerate(raw_dedup_rules):
            assert isinstance(raw_rule, dict), f"._unflake.dedup_rules.{idx} must be an attrset"
            assert (
                set(raw_rule) == {"when", "set"}
                or set(raw_rule) == {"when", "replace"}
            ), f"each dedup rule must only have .when and (.set or .replace), got {raw_rule}"

            when = raw_rule["when"]
            assert isinstance(when, dict), f"._unflake.dedup_rules.{idx}.when must be an attrset"
            for key, value in when.items():
                assert isinstance(value, FlakeRefValue | None), f"._unflake.dedup_rules.{idx}.when.{key} must be a string, int, bool or null"

            if "set" in raw_rule:
                set_ = raw_rule["set"]
                assert isinstance(set_, dict), f"._unflake.dedup_rules.{idx}.set must be an attrset"
                for key, value in set_.items():
                    assert isinstance(value, FlakeRefValue | None), f"._unflake.dedup_rules.{idx}.set.{key} must be a string, int, bool or null"
                dedup_rules.append(DedupRule(when=when, set=set_, replace=None))
            else:
                replace = raw_rule["replace"]
                assert isinstance(replace, dict | str), f"._unflake.dedup_rules.{idx}.replace must be a string or an attrset"
                if isinstance(replace, dict):
                    for key, value in replace.items():
                        assert isinstance(value, FlakeRefValue), f"._unflake.dedup_rules.{idx}.replace.{key} must be a string, int or bool"
                dedup_rules.append(DedupRule(when=when, set=None, replace=replace))

    config = Config(dedup_rules=dedup_rules)

    return config, base_deps, base_follows

async def parse_update_set(update: set[str], base_deps: dict[str, InputSpec]) -> set[StableFlakeRef]:
    result: set[StableFlakeRef] = set()
    async with asyncio.TaskGroup() as tg:
        for spec in update:
            if spec in base_deps:
                result.add(base_deps[spec].fields)
            else:
                async def do(spec: str) -> None:
                    # we don't know whether it is a flake, so we default to assuming it is
                    # this affects parsing for `file`/`tarball` inputs, biasing parsing towards `tarball`
                    flakeref = await parse_flakeref(spec, True)
                    result.add(InputSpec.from_attrs(flakeref, flake=True).fields)
                tg.create_task(do(spec))
    return result

@async_cache
async def read_nix_inputs(path: Path, inputs_kind: InputsKind) -> dict[str, object]:
    path = path.absolute()
    c = ['nix-instantiate', '--eval', '--strict', '--json']
    if inputs_kind == InputsKind.FlakeNix:
        # not all flakes have inputs :(
        c += ['--expr', '{ path }: let f = import path; in f.inputs or {}']
        c += ['--argstr', 'path']

    inputs_json = await sh(*c, str(path))
    inputs = json.loads(inputs_json)
    if inputs_kind == InputsKind.FlakeNix:
        assert isinstance(inputs, dict), f"flake at {path} has non-attrs inputs: {inputs}"

        implicit_inputs_json = await sh(
            'nix-instantiate', '--eval', '--strict', '--json',
            '--argstr', 'path', str(path),
            '--expr', '{ path }: let f = import path; in builtins.functionArgs (f.outputs or (x: x))',
        )
        implicit_inputs = json.loads(implicit_inputs_json)
        assert isinstance(implicit_inputs, dict), f"Nix returned non-attrs for functionArgs: {implicit_inputs}"
        for input in implicit_inputs:
            if input != 'self' and input not in inputs:
                inputs[input] = { 'url': input }
    else:
        assert isinstance(inputs, dict), f"inputs.nix at {path} contains non-attrs: {inputs}"

    return inputs

NIX_IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_'-]*$")
NIX_IDENT_BAD_CHARS_RE = re.compile(r'["\\$\n\r\t]')

@functools.cache
def escape_nix_ident(ident: str) -> str:
    # good case
    if NIX_IDENT_RE.match(ident) is not None:
        return ident
    # bad case
    if NIX_IDENT_BAD_CHARS_RE.search(ident) is None:
        return f'"{ident}"'
    # cursed case: let nix deal with it
    # shouldn't happen, not worth asyncifying
    return subprocess.run(
        ('nix-instantiate', '--argstr', 's', ident, '--eval', '--expr', '{ s }: s'),
        stdout=subprocess.PIPE, encoding='utf-8', check=True,
    ).stdout.strip()


# }}}

# === logging === {{{

def log(*args: object) -> None:  # pragma: no cover
    print(*args, file=sys.stderr)

def format_time(elapsed: float) -> str | None:  # pragma: no cover
    ms = int(elapsed * 1000)
    if ms < 1000/165:
        # don't log times that would be invisible on 165 FPS
        return None
    s = ms // 1000
    ms %= 1000
    m = s // 60
    s %= 60
    return " ".join(sum((
        (m > 0) * (f"{m}m",),
        (s > 0) * (f"{s}s",),
        (ms > 0) * (f"{ms}ms",),
    ), ()))

class LogSection:  # pragma: no cover
    def __init__(self, section: str) -> None:
        if VERBOSITY >= -1:
            log("#", section)
        self.started = time.monotonic()

    def done(self) -> None:
        if VERBOSITY >= 0:
            elapsed = format_time(time.monotonic() - self.started)
            if elapsed is not None:
                log(f"# ...done in {elapsed}")


    def __enter__(self) -> None:
        pass

    def __exit__(self, *_: object) -> None:
        self.done()

def log_command(args: tuple[str, ...]) -> None:  # pragma: no cover
    if VERBOSITY >= 1:
        log("$", shlex.join(args))

def format_cmd_error(err: subprocess.CalledProcessError) -> str:  # pragma: no cover
    res = f"{shlex.join(err.cmd)} returned {err.returncode}"
    if err.stderr is not None:
        stderr = err.stderr
        if isinstance(stderr, bytes):
            stderr = stderr.decode('utf-8', 'replace')
        res += f"\nstderr:\n{stderr}"
    return res

def format_http_error(err: urllib.error.HTTPError) -> str:
    return f"failed to fetch {err.url}: {err}"

def log_exceptions[T: Exception](eg: ExceptionGroup[T], fmt: Callable[[T], str]) -> None:  # pragma: no cover
    for err in eg.exceptions:
        if isinstance(err, ExceptionGroup):
            log_exceptions(err, fmt)
        else:
            log(f'error: {fmt(err)}')

# }}}

if __name__ == '__main__':  # pragma: no cover
    main()
