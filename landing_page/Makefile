PROJECT_ID = default-project
emulators:
	open http://localhost:4000
	firebase emulators:start \
		--project="default-project" \
		--only auth,firestore,hosting \
		--import=./emulator_data \
		--export-on-exit \
		--debug

clean:
	@/bin/rm -vf firebase-debug.log firestore-debug.log

deploy:
	firebase deploy --only hosting --project $(PROJECT_ID)

