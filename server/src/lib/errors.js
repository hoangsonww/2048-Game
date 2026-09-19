/**
 * One error shape for the whole API.
 *
 * Every failure a client can see is an `ApiError`, so the error middleware has
 * exactly one branch for expected failures and one for everything else. A
 * handler that throws a bare `Error` is therefore always a bug, and is reported
 * as a 500 with its detail withheld.
 */
export class ApiError extends Error {
    /**
     * @param {number} status HTTP status code.
     * @param {string} code Stable machine-readable identifier.
     * @param {string} message Human-readable summary.
     * @param {object} [details] Additional structured context, safe to expose.
     */
    constructor(status, code, message, details) {
        super(message);
        this.name = "ApiError";
        this.status = status;
        this.code = code;
        if (details !== undefined) this.details = details;
    }

    toJSON() {
        return {
            error: {
                code: this.code,
                message: this.message,
                ...(this.details === undefined ? {} : { details: this.details })
            }
        };
    }
}

export const badRequest = (message, details) => new ApiError(400, "bad_request", message, details);
export const validationFailed = details => new ApiError(422, "validation_failed", "The request body or query failed validation.", details);
export const unauthorized = (message = "Authentication is required.") => new ApiError(401, "unauthorized", message);
export const invalidCredentials = () => new ApiError(401, "invalid_credentials", "That email or password is not correct.");
export const forbidden = (message = "You do not have access to this resource.") => new ApiError(403, "forbidden", message);
export const notFound = (resource = "Resource") => new ApiError(404, "not_found", `${resource} was not found.`);
export const conflict = (message, details) => new ApiError(409, "conflict", message, details);
export const tooManyRequests = (message = "Too many requests. Slow down and try again shortly.") => new ApiError(429, "rate_limited", message);
export const featureDisabled = feature => new ApiError(503, "feature_disabled", `The ${feature} feature is disabled on this deployment.`);
export const serviceUnavailable = (message = "A dependency is unavailable.") => new ApiError(503, "service_unavailable", message);

export default ApiError;
