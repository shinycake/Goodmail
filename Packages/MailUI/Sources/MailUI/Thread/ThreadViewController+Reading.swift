public import MailCore

extension ThreadViewController {
    /// The conversation on show, where it is read and its labels now, for the window to decide where the reader goes
    /// after a change the reader asks of it.
    public var courseReader: ReaderCourse.Reader {
        ReaderCourse.Reader(viewModel.thread, mailbox: viewModel.mailbox, labels: viewModel.labels)
    }
}
