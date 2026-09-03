/// Caches [compute]'s result until [inputs] changes (compared with ==).
///
/// [I] should be a record type built from the values the computation reads;
/// [O] is typically a List/Map/Set that downstream code wants to compare by
/// identity. [inputs] is recorded only after [compute] succeeds, so a
/// throwing computation never poisons the cache with an inputs/value
/// mismatch.
class Memo<I extends Object, O> {
  I? _inputs;
  late O _value;

  O call(I inputs, O Function() compute) {
    if (_inputs == inputs) return _value;
    final value = compute();
    _inputs = inputs;
    _value = value;
    return value;
  }
}
