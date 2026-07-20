.PHONY: config config-check client-config client-config-check supabase-start supabase-stop supabase-reset functions edge-secrets smoke production-audit production-smoke extension-test server-test ios-build verify

config:
	node scripts/generate-config.mjs

config-check:
	node scripts/generate-config.mjs --check

client-config: config

client-config-check: config-check

supabase-start:
	./scripts/supabase.sh start

supabase-stop:
	./scripts/supabase.sh stop

supabase-reset:
	./scripts/supabase.sh db reset

functions: config
	node scripts/edge-env.mjs serve

edge-secrets:
	node scripts/edge-env.mjs secrets

smoke:
	node scripts/smoke-test.mjs

production-audit:
	node scripts/audit-production.mjs

production-smoke:
	node scripts/production-smoke-test.mjs

extension-test:
	node --test extension/tests/*.test.mjs
	find extension -name '*.js' -print0 | xargs -0 -n1 node --check

server-test:
	cd server && python3 -m unittest test_app.py

ios-build:
	xcodebuild -project client/CiJing.xcodeproj -scheme CiJing -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath client/.derived-data CODE_SIGNING_ALLOWED=NO build

verify: config-check extension-test server-test ios-build
