/// A fixed-size, auto-dropping circular buffer
class CircularBuffer<T extends Object> {
  final int maxLength;
  // Use a nullable type internally to safely initialize the fixed-size list.
  final List<T?> _buffer;
  int _head = 0; // Index where the next element will be written
  int _currentLength = 0; // The actual number of elements currently in the buffer

  /// Initializes the buffer with a fixed maximum size.
  CircularBuffer(this.maxLength)
    : assert(maxLength > 0),
      // Dart allows initializing a List<T?> with nulls safely.
      _buffer = List<T?>.filled(maxLength, null, growable: false);

  /// Adds a new item to the buffer. If the buffer is full, the oldest
  /// item is automatically overwritten (dropped).
  void append(T item) {
    _buffer[_head] = item;
    _head = (_head + 1) % maxLength;

    // Only increment length until the max is reached
    if (_currentLength < maxLength) {
      _currentLength++;
    }
  }

  /// Returns the actual number of elements currently in the buffer.
  int get length => _currentLength;

  /// Returns the contents of the buffer as a List`<T>`, ordered from oldest to newest.
  List<T> toList() {
    if (_currentLength == 0) {
      return <T>[];
    }

    final List<T> result = List<T>.filled(_currentLength, _buffer[0] as T);

    // The starting index for reading is the oldest element, which is the
    // element *after* the current head (where the next write will happen).
    int readStart = (_head - _currentLength + maxLength) % maxLength;

    for (int i = 0; i < _currentLength; i++) {
      int bufferIndex = (readStart + i) % maxLength;
      // We know these elements are non-null because we track _currentLength
      // and only append non-null T objects.
      result[i] = _buffer[bufferIndex] as T;
    }

    return result;
  }
}

/// A simple, non-blocking, fixed-size buffer
class FixedSizeBuffer<T> {
  final int maxSize;
  final List<T> _buffer;
  int _head = 0; // The index for the next element to be written (enqueue)
  int _tail = 0; // The index for the next element to be read (dequeue)
  int _currentSize = 0; // The actual number of elements in the buffer

  /// Initializes the buffer with a fixed maximum size.
  FixedSizeBuffer(this.maxSize)
    : assert(maxSize > 0),
      // Use a fixed-length list for efficient memory usage
      _buffer = List<T>.filled(maxSize, null as T, growable: false);

  /// Puts an item into the buffer. If the buffer is full,
  /// it will simply not add the item.
  bool put(T item) {
    if (_currentSize == maxSize) {
      // buffer is full, cannot add the item
      return false;
    }
    _buffer[_head] = item;
    _head = (_head + 1) % maxSize;
    _currentSize++;
    return true;
  }

  /// Gets an item from the buffer. Returns null if the buffer is empty.
  T? get() {
    if (_currentSize == 0) {
      // buffer is empty
      return null;
    }

    T item = _buffer[_tail];
    _tail = (_tail + 1) % maxSize;
    _currentSize--;
    return item;
  }

  int get length => _currentSize;
  bool get isFull => _currentSize == maxSize;
  bool get isEmpty => _currentSize == 0;
}
