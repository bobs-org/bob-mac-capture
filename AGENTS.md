# AGENTS.md — bob-mac-capture

Never land Swift you have not compiled, and never write a plan that tells an agent
to skip compiling.

On a host without Xcode, run `just portable-check`. If `swift` is missing, run it
on a tailnet host that has Swift (athena).

`portable-check` cannot type-check `Sources/BobMacCapture*` or
`Tests/BobMacCapture*`. When you change those, compile a scratch copy on the mac
(best effort): rsync without `.build`/`.git`, then `bundle.sh` and
`just typecheck-tests`, then delete the copy. Never use Bryan's
checkout or `just install` there.
The Mac has only Command Line Tools, which ship no XCTest, so `--build-tests` cannot
work there; `typecheck-tests` type-checks every test target against a stub, and CI
still runs the tests.

If the mac is offline, say in the final report that the macOS targets are
unverified.

After a red **Lint Swift formatting** step, check the later CI steps too — a parse
error in lint skips Build, Test, Bundle, and the install gates.

A Test step that dies at the watchdog is a hang. The sampled xctest stack in the log
or `test-hang` artifact names the stuck test. Async tests must never await an untimed
continuation or gate.
