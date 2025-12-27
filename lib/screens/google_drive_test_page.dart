import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

class GoogleDriveTestPage extends StatefulWidget {
  const GoogleDriveTestPage({super.key});

  @override
  State<GoogleDriveTestPage> createState() => _GoogleDriveTestPageState();
}

class _GoogleDriveTestPageState extends State<GoogleDriveTestPage> {
  final List<String> _logs = [];
  GoogleSignIn? _googleSignIn;
  bool _testing = false;

  void _addLog(String message) {
    setState(() {
      _logs.add('[${DateTime.now().toString().substring(11, 19)}] $message');
    });
    debugPrint('GoogleDriveTest: $message');
  }

  Future<void> _testGoogleSignIn() async {
    setState(() {
      _logs.clear();
      _testing = true;
    });

    try {
      _addLog('🔧 Initializing GoogleSignIn...');
      _googleSignIn = GoogleSignIn(
        scopes: [drive.DriveApi.driveFileScope],
      );
      _addLog('✓ GoogleSignIn initialized');

      _addLog('📱 Checking if already signed in...');
      final currentUser = _googleSignIn!.currentUser;
      if (currentUser != null) {
        _addLog('✓ Already signed in as: ${currentUser.email}');
      } else {
        _addLog('⚠ Not signed in yet');
      }

      _addLog('🔐 Starting sign-in process...');
      _addLog('Please select your Google account in the popup...');

      final account = await _googleSignIn!.signIn();

      if (account == null) {
        _addLog('❌ Sign-in cancelled by user or failed');
        setState(() => _testing = false);
        return;
      }

      _addLog('✓ Sign-in successful!');
      _addLog('📧 Email: ${account.email}');
      _addLog('👤 Display Name: ${account.displayName}');
      _addLog('🆔 ID: ${account.id}');

      _addLog('🔑 Getting authentication headers...');
      final authHeaders = await account.authHeaders;
      _addLog('✓ Auth headers obtained');
      _addLog('Headers: ${authHeaders.keys.join(", ")}');

      _addLog('☁️ Creating Drive API client...');
      final authenticateClient = GoogleAuthClient(authHeaders);
      final driveApi = drive.DriveApi(authenticateClient);
      _addLog('✓ Drive API client created');

      _addLog('📂 Testing Drive access - listing files...');
      final fileList = await driveApi.files.list(
        pageSize: 1,
        $fields: 'files(id, name)',
      );
      _addLog('✓ Drive access successful!');
      _addLog('Found ${fileList.files?.length ?? 0} files in Drive');

      _addLog('');
      _addLog('🎉 ALL TESTS PASSED!');
      _addLog('Google Drive is working correctly!');

    } catch (e, stackTrace) {
      _addLog('');
      _addLog('❌ ERROR: $e');
      _addLog('Stack trace:');
      _addLog(stackTrace.toString().substring(0, 500));
    } finally {
      setState(() => _testing = false);
    }
  }

  Future<void> _testSignOut() async {
    try {
      _addLog('🚪 Signing out...');
      await _googleSignIn?.signOut();
      _addLog('✓ Signed out successfully');
    } catch (e) {
      _addLog('❌ Sign out error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Drive Test'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                ElevatedButton(
                  onPressed: _testing ? null : _testGoogleSignIn,
                  child: _testing
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 12),
                            Text('Testing...'),
                          ],
                        )
                      : const Text('Test Google Sign-In & Drive Access'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _testing ? null : _testSignOut,
                  child: const Text('Sign Out'),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: _logs.isEmpty
                ? const Center(
                    child: Text('Tap the button above to start testing'),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      Color? color;
                      if (log.contains('❌') || log.contains('ERROR')) {
                        color = Colors.red;
                      } else if (log.contains('✓') || log.contains('🎉')) {
                        color = Colors.green;
                      } else if (log.contains('⚠')) {
                        color = Colors.orange;
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          log,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: color,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}
