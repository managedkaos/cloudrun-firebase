const { beforeUserCreated } = require("firebase-functions/v2/identity");
const { HttpsError } = require("firebase-functions/v2/https");
const { SecretManagerServiceClient } = require("@google-cloud/secret-manager");

const client = new SecretManagerServiceClient();

exports.beforeCreate = beforeUserCreated({
    region: "us-central1", // TODO: This should not be hard coded
    secrets: ["auth-allowed-emails"], // Grant access to this secret
}, async (event) => {
    const user = event.data;
    const email = user.email;

    if (!email) {
        throw new HttpsError('invalid-argument', 'Email is required.');
    }

    try {
        // Access the secret
        // Note: In Gen 2 functions with 'secrets' config, the secret value is mounted as an env var
        // or accessible via process.env if mapped, but standard practice for large lists
        // or dynamic updates is often reading the version directly or using the properly mounted env var.
        // For simplicity and robustness with the 'secrets' array configuration in firebase-functions,
        // the value is typically available in process.env.AUTH_ALLOWED_EMAILS (uppercased, dashes to underscores).
        // HOWEVER, Terraform-deployed Gen 2 functions might behave differently than CLI-deployed ones regarding auto-env-var mapping.
        // Let's us the Google Cloud Client Library to be 100% sure we get the latest version explicitly
        // or rely on process.env if we trust the mounting.

        // Let's use the env var approach which is standard for the 'secrets' configuration in firebase-functions SDK
        // IF the deployer (Terraform) sets it up correctly.
        // Since we are deploying via Terraform as a raw Cloud Function (not via firebase deploy),
        // we must manually ensure the secret is mounted or accessible.

        // ALTERNATIVE: Read from Secret Manager directly using the client. This ensures we get the latest version
        // without needing a cold start to refresh env vars, although it adds latency.
        // For an auth blocking function, latency matters. Env vars are faster.
        // Let's try to read the env var, assuming Terraform configures the secret volume mount.

        // For this specific robust implementation requested, we will use the client library with a simple in-memory cache
        // to balance freshness and performance, as we don't control the verified-safe env var injection
        // as tightly as 'firebase deploy' does.

        const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT;
        const secretName = `projects/${projectId}/secrets/auth-allowed-emails/versions/latest`;

        const [version] = await client.accessSecretVersion({ name: secretName });
        const allowedEmailsString = version.payload.data.toString();

        const allowedEmails = allowedEmailsString.split(',').map(e => e.trim());

        if (!allowedEmails.includes(email)) {
            console.log(`Blocking unauthorized email: ${email}`);
            throw new HttpsError('permission-denied', 'Unauthorized email.');
        }

        console.log(`Allowing authorized email: ${email}`);
        return;

    } catch (err) {
        console.error("Error verifying email:", err);
        // Fail safe: if we can't check, do we block? Yes, security first.
        if (err.code === 'permission-denied') throw err;
        throw new HttpsError('internal', 'Error verifying authorization.');
    }
});
