"""Every refusal the supervisor can give. `code` is what a caller matches on."""


class SlotError(Exception):
    code = "error"
    status = 500


class Invalid(SlotError):
    code = "invalid_request"
    status = 400


class Unauthorized(SlotError):
    code = "unauthorized"
    status = 401


class Forbidden(SlotError):
    code = "forbidden"
    status = 403


class NotFound(SlotError):
    code = "not_found"
    status = 404


class ProjectCapReached(SlotError):
    code = "project_cap_reached"
    status = 409


class ServerLimitReached(SlotError):
    code = "server_limit_reached"
    status = 409


class ConfigError(SlotError):
    code = "config_error"
    status = 500


class RuntimeFailed(SlotError):
    code = "runtime_failed"
    status = 500
