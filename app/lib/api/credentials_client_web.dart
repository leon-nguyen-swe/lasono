import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

/// The client for requests that carry the refresh cookie. A browser sends
/// cookies to another origin (the app on :3000, the API on :8080) only when the
/// request asks for credentials.
http.Client createCredentialsClient() => BrowserClient()..withCredentials = true;
