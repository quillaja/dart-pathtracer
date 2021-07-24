import 'dart:isolate';

/// A function type where work is done. Incoming job data
/// is received on RecievePort and finished result data is sent on
/// SendPort.
typedef WorkFunction = void Function(ReceivePort, SendPort);

/// Data to initialize a worker isolate.
class _isolateData {
  SendPort sendInputQueue;
  WorkFunction work;
  SendPort resultPort;

  _isolateData(this.sendInputQueue, this.work, this.resultPort);
}

/// Function that 'connects' worker isolate and controller isolate.
void _isolateFunction(_isolateData init) {
  final dataInput = ReceivePort();
  init.sendInputQueue.send(dataInput.sendPort);
  init.work(dataInput, init.resultPort);
}

/// WorkerPool creates and manages a number of isolates to perform some
/// task provided by a WorkFunction.
class WorkerPool<Job> {
  final int _numWorkers;
  int _jobs;
  final bool _stopWhenJobsEmpty;
  final List<SendPort> _queues;
  final List<Isolate> _workers;
  final ReceivePort _resultPort;
  final WorkFunction _work;

  WorkerPool(int numWorkers, WorkFunction workFunction,
      [bool stopWhenJobsEmpty = true])
      : _numWorkers = numWorkers,
        _jobs = 0,
        _stopWhenJobsEmpty = stopWhenJobsEmpty,
        _queues = <SendPort>[],
        _workers = <Isolate>[],
        _resultPort = ReceivePort(),
        _work = workFunction;

  /// Create and start worker isolates.
  Future<void> start() async {
    var queuePort = ReceivePort();

    // make isolates
    // send them the necessary bits via _isolateData
    for (var i = 0; i < _numWorkers; i++) {
      var iso = await Isolate.spawn<_isolateData>(_isolateFunction,
          _isolateData(queuePort.sendPort, _work, _resultPort.sendPort));
      _workers.add(iso);
    }
    // get a port from each isolate
    await for (var q in queuePort) {
      _queues.add(q);
      if (_queues.length == _numWorkers) queuePort.close();
    }
  }

  /// The ReceivePort on which finished result data from workers is returned.
  ReceivePort get results => _resultPort;

  /// The number of jobs in the work queue(s).
  int get jobs => _jobs;

  /// Add a job to the work queue(s).
  void add(Job work) {
    var workerIndex = _jobs % _numWorkers;
    _jobs++;
    _queues[workerIndex].send(work);
  }

  /// Add all jobs to the work queue(s).
  void addAll(List<Job> work) => work.forEach((e) => add(e));

  /// Signal that a single item of work was completed.
  void done() {
    _jobs--;
    if (_jobs == 0 && _stopWhenJobsEmpty) stop();
  }

  // Close the results ReceivePort and terminate the worker isolates.
  void stop() {
    _resultPort.close();
    _workers.forEach((iso) => iso.kill());
  }
}
