/// The outcome of handing a rendered receipt to the print pipeline.
///
/// Lives in its own file, rather than beside `PrintQueueService` which
/// produces it or `PrinterService` which consumes it, because those two
/// deliberately do not import each other: `PrintQueueService` depends on
/// `PrinterService` for transport, and an import back the other way would
/// close a real circular dependency. Both already import this directory's
/// plain data types, so the shared vocabulary belongs here.
///
/// Wider than the plain `(ok, error)` the transport layer returns, because a
/// relayed job has a third outcome that is neither success nor failure:
///
///  * `ok: true` — the receipt came out of a printer.
///  * `deferred: true` — the job is real, persisted, and still being retried,
///    but the terminal that owns its printer is not answering right now. The
///    caller must neither block on it (that terminal may be minutes away) nor
///    report a failure (nothing has been lost); the receipt prints by itself
///    when the owner comes back.
///  * neither — it failed, and [error] says why.
typedef PrintDispatchResult = ({bool ok, String? error, bool deferred});
