class AuthenticationError(Exception):
    """Authentication credentials are invalid, expired, or unusable."""


class DuplicateEmailError(Exception):
    """A normalized email address is already registered."""
