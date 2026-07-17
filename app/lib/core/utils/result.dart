/// 軽量Result型。Repositoryの戻り値で例外を型として表現したい箇所に使用。
sealed class Result<T> {
  const Result();
  R when<R>({
    required R Function(T value) success,
    required R Function(Object error) failure,
  }) =>
      switch (this) {
        Success(:final value) => success(value),
        Failure(:final error) => failure(error),
      };
}

final class Success<T> extends Result<T> {
  const Success(this.value);
  final T value;
}

final class Failure<T> extends Result<T> {
  const Failure(this.error);
  final Object error;
}
