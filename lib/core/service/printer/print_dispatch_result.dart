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

/// One transport-level attempt at putting bytes through a printer.
///
/// [connectFailed] is the half that matters beyond logging: `true` means the
/// attempt never got a connection, so **nothing reached the printer** and the
/// same bytes may safely be sent again — by this terminal or, via the LAN
/// relay, by one that can actually reach it. `false` covers everything else,
/// including a socket that opened and then broke mid-write: those bytes may
/// have been partly printed, and re-sending them is how a customer ends up
/// with two receipts. It is `false` whenever the transport cannot tell.
typedef PrintAttempt = ({bool ok, String? error, bool connectFailed});
