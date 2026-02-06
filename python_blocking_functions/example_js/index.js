const { beforeUserCreated, beforeUserSignedIn } = require("firebase-functions/v2/identity");
const { HttpsError } = require("firebase-functions/v2/https");

// Helper function to keep it DRY (Don't Repeat Yourself)
const validateEmail = (event) => {
    // 0. Get the email address
    const email = event.data?.email?.toLowerCase();

    // 1. Access the secret from process.env (injected by Cloud Run/Firebase)
    const rawAllowedEmails = process.env.AUTH_ALLOWED_EMAILS;

    // 2. Check for the email
    if (!email) {
        throw new HttpsError('invalid-argument', 'Email is required.');
    }

    // 3. Check for the allowed emails; fatal error is not present
    // because auth-allowed-emails secret is not mounted or empty
    if (!rawAllowedEmails) {
        throw new HttpsError('internal', 'Configuration error.');
    }

    // 4. Parse and check (Consider caching the split array outside the handler if the list is huge)
    const allowedEmails = rawAllowedEmails.split(',').map(e => e.trim().toLowerCase());

    // 5. If the email is not in the allowedEmails list, block it
    if (!allowedEmails.includes(email)) {
        console.warn(`${email} is unauthorized.  Access is denied.`);
        throw new HttpsError('permission-denied', 'The email is not on the authorized list.');
    }

    return;
};

// Signup Trigger; Runs before the user is created
exports.beforeCreate = beforeUserCreated({
    secrets: ["auth-allowed-emails"],
}, (event) => validateEmail(event));

// Login Trigger; Runs before any user logs in
exports.beforeSignIn = beforeUserSignedIn({
    secrets: ["auth-allowed-emails"],
}, (event) => validateEmail(event));
