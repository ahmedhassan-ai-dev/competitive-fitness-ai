import 'package:flutter/material.dart';

import '../../shared/ui.dart';
import '../../shared/fitarena_brand.dart';
import '../../services/fitness_api.dart';
import '../home/home_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(centerTitle: true, title: const FitArenaBrandHeader()),
    body: PageBody(
      children: [
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF123D30),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FitArenaMark(size: 68),
              const SizedBox(height: 24),
              Text(
                'Your next rep.\nYour next level.',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Move with purpose. Build consistency. Challenge each other.',
                style: TextStyle(color: Color(0xFFE0EBE4), fontSize: 17),
              ),
            ],
          ),
        ),
        FilledButton(
          onPressed: () => openPage(context, const AuthScreen()),
          child: const Text('Log in'),
        ),
        OutlinedButton(
          onPressed: () => openPage(context, const AuthScreen(register: true)),
          child: const Text('Create account'),
        ),
        TextButton(
          onPressed: () => _enterDemo(context),
          child: const Text('Explore demo'),
        ),
        InfoCard(
          icon: Icons.science_outlined,
          title: 'Explore FitArena',
          message: FitnessApi.instance.isConfigured
              ? 'Live multiplayer needs a server connection; Explore demo is still available offline.'
              : 'A local demo with simulated workouts and sample challenges. No account or camera needed.',
        ),
      ],
    ),
  );
}

void _enterDemo(BuildContext context) => Navigator.of(context)
    .pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.register = false});
  final bool register;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _username = TextEditingController();
  String? _error;
  bool _hidden = true;
  bool _loading = false;

  @override
  void dispose() {
    _password.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    if (!FitnessApi.instance.isConfigured) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (mounted) _enterDemo(context);
      return;
    }
    try {
      await FitnessApi.instance.authenticate(username: _username.text.trim(),
        password: _password.text, register: widget.register);
      if (mounted) _enterDemo(context);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(centerTitle: true, title: const FitArenaBrandHeader()),
    body: PageBody(
      children: [
        SectionHeading(
          widget.register
              ? 'Start your next chapter.'
              : 'Ready for another rep?',
          subtitle:
              FitnessApi.instance.isConfigured
              ? 'Use your account to join live friends rooms.'
              : 'Demo only. Use made-up credentials; nothing is sent or saved.',
        ),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _username,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enabled: !_loading,
                validator: (value) =>
                    RegExp(r'^[A-Za-z0-9_]{3,32}$').hasMatch(value ?? '')
                    ? null
                    : 'Use 3–32 letters, numbers, or underscores.',
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _password,
                enabled: !_loading,
                obscureText: _hidden,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _hidden ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _hidden = !_hidden),
                    icon: Icon(
                      _hidden
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) =>
                    (value?.length ?? 0) >= 12 && (value?.length ?? 0) <= 128
                    ? null
                    : 'Use 12–128 characters.',
                onFieldSubmitted: (_) {
                  if (!_loading) _submit();
                },
              ),
              if (widget.register) ...[
                const SizedBox(height: 20),
                TextFormField(
                  enabled: !_loading,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                  ),
                  validator: (value) =>
                      value == _password.text ? null : 'Passwords must match.',
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          semanticsLabel: 'Opening demo',
                        ),
                      )
                    : Text(
                        widget.register
                            ? (FitnessApi.instance.isConfigured ? 'Create account' : 'Create demo account')
                            : (FitnessApi.instance.isConfigured ? 'Log in' : 'Continue to demo'),
                      ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
