// scripts/build.mjs — prepare the rp npm package for publishing.
//
// rp is a plain Bash CLI, so "building" is light: stamp the version into
// package.json (from a `--version` arg, the CI tag in $GITHUB_REF_NAME, or the
// version already in package.json) and verify the files that `npm publish`
// will ship actually exist and are executable. There is deliberately NO npm
// lifecycle hook (no prepare/prepack) — the release workflow runs this
// explicitly via `node scripts/build.mjs` before `npm publish --provenance`.
//
// Usage:
//   node scripts/build.mjs                stamp from $GITHUB_REF_NAME (fallback: package.json)
//   node scripts/build.mjs --version 1.0.0   stamp an explicit version
//   node scripts/build.mjs --check          verify only; never write package.json

import {
	chmodSync,
	existsSync,
	readFileSync,
	statSync,
	writeFileSync,
} from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(import.meta.dirname, "..");
const PKG = resolve(ROOT, "package.json");

// Files the published package must contain (kept in lockstep with the
// `files` array in package.json). These are the repo-root dirs/bin, not a dist.
const FILES = ["bin/rp", "lib", "commands", "LICENSE"];

function die(msg) {
	process.stderr.write(`build: error: ${msg}\n`);
	process.exit(1);
}

function resolveVersion() {
	const argv = process.argv.slice(2);
	const vi = argv.indexOf("--version");
	if (vi !== -1 && argv[vi + 1]) return argv[vi + 1].replace(/^v/, "");

	const ref = process.env.GITHUB_REF_NAME;
	if (ref) return ref.replace(/^v/, "");

	try {
		const pkg = JSON.parse(readFileSync(PKG, "utf8"));
		if (pkg.version && pkg.version !== "0.0.0-dev") return pkg.version;
	} catch {
		/* fall through */
	}
	die(
		"could not determine a version (pass --version x.y.z or set GITHUB_REF_NAME)",
	);
}

function isValidVersion(v) {
	return /^[0-9]+\.[0-9]+\.[0-9]+$/.test(v);
}

function stampVersion(version) {
	const pkg = JSON.parse(readFileSync(PKG, "utf8"));
	if (pkg.version === version) {
		process.stdout.write(`build: package.json already at ${version}\n`);
		return;
	}
	pkg.version = version;
	writeFileSync(PKG, JSON.stringify(pkg, null, 2) + "\n");
	process.stdout.write(`build: stamped package.json -> ${version}\n`);
}

function verifyFiles() {
	let ok = true;
	for (const f of FILES) {
		const p = resolve(ROOT, f);
		if (!existsSync(p)) {
			process.stderr.write(`build: missing publish file: ${f}\n`);
			ok = false;
			continue;
		}
		if (f === "bin/rp") {
			// npm relies on the bin's executable bit; set it defensively so a stray
			// umask (or a checkout that dropped the bit) can't break `npx rp`.
			const mode = statSync(p).mode;
			if (!(mode & 0o111)) {
				process.stdout.write(`build: bin/rp not executable; chmod +x\n`);
				chmodSync(p, 0o755);
			}
		}
	}
	return ok;
}

function main() {
	const checkOnly = process.argv.slice(2).includes("--check");
	const version = resolveVersion();
	if (!isValidVersion(version))
		die(`invalid version '${version}' — expected x.y.z`);

	if (!verifyFiles()) die("publish files incomplete; aborting");
	if (checkOnly) {
		process.stdout.write(`build: --check ok for ${version}\n`);
	} else {
		stampVersion(version);
	}
	process.stdout.write(`build: ready to publish @objctp/rp@${version}\n`);
}

main();
