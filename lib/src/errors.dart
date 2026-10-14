/// Base class of every error the library throws.
class EdgeMLException implements Exception {
  /// Creates an exception with a [message] and, for server errors, the HTTP
  /// [statusCode].
  const EdgeMLException(this.message, {this.statusCode});

  /// What went wrong, including the server's explanation where there is one.
  final String message;

  /// The HTTP status code, if the server answered with an error.
  final int? statusCode;

  @override
  String toString() => statusCode == null ? 'EdgeMLException: $message' : 'EdgeMLException($statusCode): $message';
}

/// The API key is unknown, or a read key was used for something that needs
/// the write key (HTTP 401).
class AuthenticationException extends EdgeMLException {
  /// Creates an [AuthenticationException].
  const AuthenticationException(super.message) : super(statusCode: 401);
}

/// A dataset or model does not exist in the project (HTTP 404).
class NotFoundException extends EdgeMLException {
  /// Creates a [NotFoundException].
  const NotFoundException(super.message) : super(statusCode: 404);
}

/// Training failed on the server or did not finish in time.
class TrainingException extends EdgeMLException {
  /// Creates a [TrainingException].
  const TrainingException(super.message, {this.modelId});

  /// The id of the model that failed.
  final String? modelId;
}

/// [Predictor.predict] was called before a full window of samples was
/// buffered. Check [Predictor.isReady] first, or catch this and try again.
class PredictorNotReadyException extends EdgeMLException {
  /// Creates a [PredictorNotReadyException].
  const PredictorNotReadyException(super.message);
}
