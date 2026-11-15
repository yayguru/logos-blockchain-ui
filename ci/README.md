# Windows .lgx CI (ready to enable)

`windows-lgx.yml` builds the Windows x86_64 `.lgx` on GitHub Actions with Nix
(mingw cross build), checks it (Linux unit tests / compile check), signs it
when the `LGX_SIGNING_JWK` repository secret is set, and uploads the package
plus `SHA256SUMS` as a workflow artifact. Without the secret it uploads an
unsigned package (Basecamp then shows it as unsigned).

It lives here and not in `.github/workflows/` only because the token used to
push this branch has no `workflow` scope. To enable it (repo owner, once):

```sh
gh auth refresh -s workflow
mkdir -p .github/workflows && git mv ci/windows-lgx.yml .github/workflows/
git commit -m "CI: enable windows-lgx" && git push
# optional signing; the key is read from the file and never printed:
gh secret set LGX_SIGNING_JWK -R yayguru/<repo> < /path/to/yayguru.jwk
```

Optional: add `'!v*-windows.*'` under `on.push.tags` in the upstream
`release.yml` so the fork's windows tags do not start that workflow.

Timing: Qt for mingw is not in any public binary cache, so the first run
builds qtbase + qtdeclarative from source (about 3-5 h on a 4-core runner,
the job limit is 350 min). The Nix store is then cached
(`nix-community/cache-nix-action`, 9 GB cap) and later runs only rebuild
the plugin (minutes).
