import 'package:flutter/material.dart';
import 'package:zedbiz/app/app_controller.dart';

// Copy zedbiz_workspace.jpg to mobile/assets/images/ and register it in
// mobile/pubspec.yaml under flutter: assets: - assets/images/zedbiz_workspace.jpg
const _forest = Color(0xFF083A2B);
const _green = Color(0xFF167A4A);
const _mint = Color(0xFF7CF0A8);
const _photo = 'assets/images/zedbiz_workspace.jpg';

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
    backgroundColor: Colors.white,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 850;
          final hero = _PhotoHero(desktop: desktop);
          final panel = _AuthPanel(
            controller: widget.controller,
            registering: _registering,
            onToggleMode: _toggleMode,
            desktop: desktop,
          );
          if (desktop) {
            return Row(
              children: [
                Expanded(flex: 11, child: hero),
                Expanded(
                  flex: 10,
                  child: ColoredBox(
                    color: const Color(0xFFFCFDFC),
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 24,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 490),
                          child: panel,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                hero,
                Transform.translate(
                  offset: const Offset(0, -30),
                  child: panel,
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _PhotoHero extends StatelessWidget {
  const _PhotoHero({required this.desktop});
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: desktop ? double.infinity : 440,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: _forest),
          Image.asset(
            _photo,
            fit: BoxFit.cover,
            alignment: Alignment.centerRight,
            errorBuilder: (context, error, stackTrace) => const ColoredBox(color: _forest),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  const Color(0xFF002D20).withValues(alpha: 0.96),
                  const Color(0xFF003824).withValues(alpha: 0.78),
                  const Color(0xFF00351F).withValues(alpha: 0.24),
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.10),
                  Colors.transparent,
                  const Color(0xFF001B13).withValues(alpha: 0.30),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              desktop ? 56 : 26,
              desktop ? 64 : 32,
              desktop ? 40 : 22,
              desktop ? 50 : 58,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: desktop
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.storefront_outlined,
                      color: Colors.white,
                      size: 45,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text.rich(
                          TextSpan(children: [
                            TextSpan(text: 'Zed', style: TextStyle(color: Colors.white)),
                            TextSpan(text: 'Biz', style: TextStyle(color: _mint)),
                          ]),
                          style: TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.9,
                            height: 1.1,
                          ),
                        ),
                        Text(
                          'Business Made Simple',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: desktop ? 70 : 44),
                Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'Manage\nYour Business\nAnytime,\n'),
                    const TextSpan(
                      text: 'Anywhere.',
                      style: TextStyle(color: _mint),
                    ),
                  ]),
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    height: 1.12,
                    letterSpacing: -0.7,
                    fontSize: desktop ? 42 : 33,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Track sales, manage products,\nand grow your business with ZedBiz.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.96),
                    fontSize: desktop ? 16 : 14,
                    height: 1.45,
                  ),
                ),
                if (desktop) ...[
                  const SizedBox(height: 42),
                  const _Feature(icon: Icons.bar_chart_rounded, title: 'Track sales', subtitle: 'Monitor your business activity.'),
                  const SizedBox(height: 19),
                  const _Feature(icon: Icons.inventory_2_outlined, title: 'Manage products', subtitle: 'Keep inventory organized.'),
                  const SizedBox(height: 19),
                  const _Feature(icon: Icons.trending_up_rounded, title: 'Grow with insights', subtitle: 'Make informed business decisions.'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: _green.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
      const SizedBox(width: 12),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(color: Color(0xFFE5F2E9), fontSize: 12)),
        ],
      ),
    ],
  );
}

class _AuthPanel extends StatelessWidget {
  const _AuthPanel({
    required this.controller,
    required this.registering,
    required this.onToggleMode,
    required this.desktop,
  });
  final AppController controller;
  final bool registering;
  final VoidCallback onToggleMode;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(desktop ? 28 : 34),
          topRight: Radius.circular(desktop ? 28 : 34),
          bottomLeft: Radius.circular(desktop ? 28 : 0),
          bottomRight: Radius.circular(desktop ? 28 : 0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 80,
            child: IgnorePointer(child: CustomPaint(painter: _MintWaves())),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              desktop ? 34 : 26,
              desktop ? 42 : 34,
              desktop ? 34 : 26,
              desktop ? 95 : 96,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  registering ? 'Create your account' : 'Welcome back',
                  style: TextStyle(
                    fontSize: desktop ? 29 : 27,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF17221C),
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  registering
                      ? 'Join ZedBiz and start managing your business.'
                      : 'Sign in to your ZedBiz account to continue.',
                  style: const TextStyle(color: Color(0xFF68746E), fontSize: 13),
                ),
                const SizedBox(height: 24),
                if (registering)
                  RegistrationForm(controller: controller)
                else
                  LoginForm(controller: controller),
                if (controller.busy) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Connecting securely. The first request may take a minute; please wait.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Color(0xFF68786E)),
                  ),
                ],
                const SizedBox(height: 18),
                TextButton(
                  onPressed: controller.busy ? null : onToggleMode,
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: registering
                            ? 'Already have an account? '
                            : 'New to ZedBiz? ',
                        style: const TextStyle(color: Color(0xFF52615A)),
                      ),
                      TextSpan(
                        text: registering ? 'Sign in' : 'Create an account',
                        style: const TextStyle(
                          color: _green,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ]),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MintWaves extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final back = Paint()..color = const Color(0xFFDDF5E6);
    final middle = Paint()..color = const Color(0xFFB7E8C9);
    final front = Paint()..color = const Color(0xFF84D3A3);
    final p1 = Path()
      ..moveTo(0, 20)
      ..cubicTo(size.width * .22, -10, size.width * .33, 82, size.width * .58, 49)
      ..cubicTo(size.width * .78, 15, size.width * .84, 60, size.width, 36)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(p1, back);
    final p2 = Path()
      ..moveTo(0, 44)
      ..cubicTo(size.width * .2, 10, size.width * .42, 105, size.width * .66, 66)
      ..cubicTo(size.width * .82, 48, size.width * .88, 70, size.width, 60)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(p2, middle);
    final p3 = Path()
      ..moveTo(0, 66)
      ..cubicTo(size.width * .19, 34, size.width * .33, 96, size.width * .55, 80)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(p3, front);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
  bool _showPassword = false;

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
        TextFormField(
          key: const Key('login-email'),
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          decoration: _fieldDecoration(
            label: 'Email address',
            icon: Icons.email_outlined,
          ),
          validator: _emailValidator,
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('login-password'),
          controller: _password,
          obscureText: !_showPassword,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) {
            if (!widget.controller.busy) _submit();
          },
          decoration: _fieldDecoration(
            label: 'Password',
            icon: Icons.lock_outline_rounded,
          ).copyWith(
            suffixIcon: IconButton(
              tooltip: _showPassword ? 'Hide password' : 'Show password',
              icon: Icon(
                _showPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
          validator: (value) =>
              (value?.isEmpty ?? true) ? 'Enter your password' : null,
        ),
        _ErrorMessage(widget.controller.errorMessage),
        const SizedBox(height: 22),
        _PrimaryAuthButton(
          buttonKey: const Key('login-submit'),
          busy: widget.controller.busy,
          onPressed: widget.controller.busy ? null : _submit,
          label: 'Sign in',
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
  bool _showPassword = false;

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
        TextFormField(
          key: const Key('register-name'),
          controller: _fullName,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: _fieldDecoration(
            label: 'Full name',
            icon: Icons.person_outline_rounded,
          ),
          validator: (value) =>
              (value?.trim().length ?? 0) < 2 ? 'Enter your full name' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('register-email'),
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          decoration: _fieldDecoration(
            label: 'Email address',
            icon: Icons.email_outlined,
          ),
          validator: _emailValidator,
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('register-password'),
          controller: _password,
          obscureText: !_showPassword,
          textInputAction: TextInputAction.next,
          decoration: _fieldDecoration(
            label: 'Password',
            icon: Icons.lock_outline_rounded,
          ).copyWith(
            helperText: 'Use at least 8 characters',
            suffixIcon: IconButton(
              tooltip: _showPassword ? 'Hide password' : 'Show password',
              icon: Icon(
                _showPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
          validator: (value) => (value?.length ?? 0) < 8
              ? 'Password must have at least 8 characters'
              : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('register-confirm'),
          controller: _confirmation,
          obscureText: !_showPassword,
          textInputAction: TextInputAction.done,
          decoration: _fieldDecoration(
            label: 'Confirm password',
            icon: Icons.verified_user_outlined,
          ),
          validator: (value) =>
              value != _password.text ? 'Passwords do not match' : null,
        ),
        _ErrorMessage(widget.controller.errorMessage),
        const SizedBox(height: 22),
        _PrimaryAuthButton(
          buttonKey: const Key('register-submit'),
          busy: widget.controller.busy,
          onPressed: widget.controller.busy ? null : _submit,
          label: 'Create account',
        ),
      ],
    ),
  );
}

InputDecoration _fieldDecoration({
  required String label,
  required IconData icon,
}) => InputDecoration(
  labelText: label,
  prefixIcon: Icon(icon, size: 21),
  filled: true,
  fillColor: const Color(0xFFF7FAF7),
  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(13),
    borderSide: const BorderSide(color: Color(0xFFDDE8DF)),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(13),
    borderSide: const BorderSide(color: Color(0xFFDDE8DF)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(13),
    borderSide: const BorderSide(color: Color(0xFF287C54), width: 1.8),
  ),
);

class _PrimaryAuthButton extends StatelessWidget {
  const _PrimaryAuthButton({
    required this.buttonKey,
    required this.busy,
    required this.onPressed,
    required this.label,
  });

  final Key buttonKey;
  final bool busy;
  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    child: FilledButton(
      key: buttonKey,
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF1E6A49),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
        ),
      ),
      child: busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.arrow_forward_rounded, size: 19),
              ],
            ),
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
