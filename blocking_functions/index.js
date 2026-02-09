const { beforeUserCreated, beforeUserSignedIn } = require("firebase-functions/v2/identity");
const { HttpsError } = require("firebase-functions/v2/https");

// Helper function to keep it DRY (Don't Repeat Yourself)
const validateEmail = (event) => {
    // 0. Get the email address and make it lowercase
    const email = event.data?.email?.toLowerCase();

    // 1. Check for the email and throw an error if the email is not present
    if (!email) {
        throw new HttpsError('invalid-argument', 'Email is required.');
    }

    // 2. Access the secret "auth-allowed-emails"
    const rawAllowedEmails = process.env.AUTH_ALLOWED_EMAILS;


    // 3. Check for the allowed emails list; Throw a fatal error if the list is not present or empty
    if (!rawAllowedEmails) {
        throw new HttpsError('internal', 'Configuration error.');
    }

    // 4. If the email is not in the allowedEmails list, block it
    const allowedEmails = rawAllowedEmails.split(',').map(e => e.trim().toLowerCase());

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
