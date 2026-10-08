import 'package:http/http.dart' as http;

/// The client for requests that carry the refresh cookie. Outside a browser
/// there is no cookie to switch on, so this is the ordinary client.
http.Client createCredentialsClient() => http.Client();
