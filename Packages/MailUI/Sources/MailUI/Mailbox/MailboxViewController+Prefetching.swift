import MailCore
public import UIKit

/// Rows about to scroll in start loading what drawing and opening them needs, a screen or so ahead: their senders'
/// pictures and their threads' bodies. Rows the scroll turns away from before their turn leave the bodies' queue.
extension MailboxViewController: UICollectionViewDataSourcePrefetching {
    public func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let ids = indexPaths.compactMap(dataSource.itemIdentifier(for:))
        if display.showsAvatars, let pictures = collectionView.traitCollection.senderPictures {
            pictures.warm(ids.compactMap { threadsByID[$0]?.sender.address })
        }
        viewModel.readAhead(ids, because: .visible)
    }

    public func collectionView(
        _ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]
    ) {
        viewModel.skipReadAhead(indexPaths.compactMap(dataSource.itemIdentifier(for:)))
    }
}
