import 'package:flutter/material.dart';
import 'package:zedbiz/app/app_controller.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({required this.controller, super.key});

  final AppController controller;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _registering = false;

  void _toggleMode() {
    widget.controller.clearError();
    setState(() => _registering = !_registering);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              children: [
                Icon(
                  Icons.storefront,
                  size: 52,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  'ZedBiz',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  _registering
                      ? 'Create your business account'
                      : 'Welcome back',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 28),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _registering
                        ? RegistrationForm(controller: widget.controller)
                        : LoginForm(controller: widget.controller),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: widget.controller.busy ? null : _toggleMode,
                  child: Text(
                    _registering
                        ? 'Already have an account? Sign in'
                        : 'New to ZedBiz? Create an account',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class LoginForm extends StatefulWidget {
  const LoginForm({required this.controller, super.key});
  final AppController controller;

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await widget.controller.login(
      email: _email.text.trim(),
      password: _password.text,
    );
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Sign in', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 20),
        TextFormField(
          key: const Key('login-email'),
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Email address',
            prefixIcon: Icon(Icons.email_outlined),
          ),
          validator: _emailValidator,
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('login-password'),
          controller: _password,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: const InputDecoration(
            labelText: 'Password',
            prefixIcon: Icon(Icons.lock_outline),
          ),
          validator: (value) =>
              (value?.isEmpty ?? true) ? 'Enter your password' : null,
        ),
        _ErrorMessage(widget.controller.errorMessage),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('login-submit'),
          onPressed: widget.controller.busy ? null : _submit,
          child: widget.controller.busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Sign in'),
        ),
      ],
    ),
  );
}

class RegistrationForm extends StatefulWidget {
  const RegistrationForm({required this.controller, super.key});
  final AppController controller;

  @override
  State<RegistrationForm> createState() => _RegistrationFormState();
}

class _RegistrationFormState extends State<RegistrationForm> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await widget.controller.register(
      fullName: _fullName.text.trim(),
      email: _email.text.trim(),
      password: _password.text,
    );
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Create account',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 20),
        TextFormField(
          key: const Key('register-name'),
          controller: _fullName,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Full name',
            prefixIcon: Icon(Icons.person_outline),
          ),
          validator: (value) =>
              (value?.trim().length ?? 0) < 2 ? 'Enter your full name' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('register-email'),
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email address',
            prefixIcon: Icon(Icons.email_outlined),
          ),
          validator: _emailValidator,
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('register-password'),
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            helperText: 'Use at least 8 characters',
          ),
          validator: (value) => (value?.length ?? 0) < 8
              ? 'Password must have at least 8 characters'
              : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('register-confirm'),
          controller: _confirmation,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Confirm password'),
          validator: (value) =>
              value != _password.text ? 'Passwords do not match' : null,
        ),
        _ErrorMessage(widget.controller.errorMessage),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('register-submit'),
          onPressed: widget.controller.busy ? null : _submit,
          child: widget.controller.busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create account'),
        ),
      ],
    ),
  );
}

String? _emailValidator(String? value) {
  final email = value?.trim() ?? '';
  return email.contains('@') && email.contains('.')
      ? null
      : 'Enter a valid email address';
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage(this.message);
  final String? message;

  @override
  Widget build(BuildContext context) => message == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            message!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        );
}
