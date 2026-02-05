const functions = require('@google-cloud/functions-framework');

// Helper function to decode JWT (without verification since it's already verified by Firebase)
const decodeJWT = (token) => {
    try {
        const parts = token.split('.');
        if (parts.length !== 3) {
            throw new Error('Invalid JWT format');
        }
        
        // Decode the payload (middle part)
        const payload = JSON.parse(Buffer.from(parts[1], 'base64').toString('utf8'));
        return payload;
    } catch (error) {
        console.error('Failed to decode JWT:', error);
        throw new Error('Invalid JWT token');
    }
};

// Helper function to validate email
const validateEmail = (email) => {
    if (!email) {
        throw new Error('Email is required.');
    }

    // Access the secret from process.env
    const rawAllowedEmails = process.env.AUTH_ALLOWED_EMAILS;

    if (!rawAllowedEmails) {
        console.error('AUTH_ALLOWED_EMAILS environment variable is missing or empty');
        throw new Error('Configuration error: authorized emails list not found.');
    }

    // Parse allowed emails
    const allowedEmails = rawAllowedEmails
        .split(',')
        .map(e => e.trim().toLowerCase())
        .filter(e => e.length > 0);

    console.log(`Validating email: ${email} against ${allowedEmails.length} allowed emails`);

    // Check if email is allowed
    if (!allowedEmails.includes(email.toLowerCase())) {
        console.warn(`Access denied: ${email} is not authorized`);
        throw new Error('This email is not authorized.');
    }

    console.log(`Access granted: ${email} is authorized`);
};

// Before Create Handler
functions.http('beforeCreate', async (req, res) => {
    try {
        console.log('=== beforeCreate triggered ===');

        // Extract JWT from request
        const jwt = req.body?.data?.jwt;
        if (!jwt) {
            throw new Error('JWT token is missing from request');
        }

        // Decode JWT to get user data
        const payload = decodeJWT(jwt);
        console.log('JWT payload:', JSON.stringify(payload, null, 2));

        // Extract email from user_record in the JWT
        const email = payload.user_record?.email;
        console.log('Extracted email:', email);

        validateEmail(email);

        // Return success
        res.status(200).json({});
    } catch (error) {
        console.error('Error in beforeCreate:', error);
        res.status(400).json({
            error: {
                message: error.message || 'An error occurred',
                status: 'INVALID_ARGUMENT'
            }
        });
    }
});

// Before Sign In Handler
functions.http('beforeSignIn', async (req, res) => {
    try {
        console.log('=== beforeSignIn triggered ===');

        // Extract JWT from request
        const jwt = req.body?.data?.jwt;
        if (!jwt) {
            throw new Error('JWT token is missing from request');
        }

        // Decode JWT to get user data
        const payload = decodeJWT(jwt);
        console.log('JWT payload:', JSON.stringify(payload, null, 2));

        // Extract email from user_record in the JWT
        const email = payload.user_record?.email;
        console.log('Extracted email:', email);

        validateEmail(email);

        // Return success
        res.status(200).json({});
    } catch (error) {
        console.error('Error in beforeSignIn:', error);
        res.status(400).json({
            error: {
                message: error.message || 'An error occurred',
                status: 'INVALID_ARGUMENT'
            }
        });
    }
});