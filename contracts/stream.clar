;; title: Token Stream
;; version: 1.0.0
;; summary: A smart contract for streaming tokens over time on the Stacks blockchain.
;; description: This contract allows users to create token streams, enabling continuous payments over a specified timeframe.

;; traits
;;

;; token definitions
;;

;; constants
;; Error codes
(define-constant ERR_UNAUTHORIZED (err u0))
(define-constant ERR_INVALID_SIGNATURE (err u1))
(define-constant ERR_STREAM_STILL_ACTIVE (err u2))
(define-constant ERR_INVALID_STREAM_ID (err u3))

;; data vars
(define-data-var latest-stream-id uint u0)

;; data maps
;; Streams mapping
(define-map streams
    uint ;; stream id
    {
        sender: principal,
        recepient: principal,
        balance: uint,
        withdrawn-balance: uint,
        payment-per-block: uint,
        timeframe: {
            start-block: uint,
            end-block: uint,
        },
    }
)

;; public functions
;; Create a new stream
(define-public (stream-to
        (recepient principal)
        (initial-balance uint)
        (timeframe {
            start-block: uint,
            end-block: uint,
        })
        (payment-per-block uint)
    )
    (let (
            (stream {
                sender: contract-caller,
                recepient: recepient,
                balance: initial-balance,
                withdrawn-balance: u0,
                payment-per-block: payment-per-block,
                timeframe: timeframe,
            })
            (current-stream-id (var-get latest-stream-id))
        )
        ;; 'as-contract tx-sender' is like 'address(this)'
        (try! (stx-transfer? initial-balance contract-caller (as-contract tx-sender)))
        (map-set streams current-stream-id stream)
        (var-set latest-stream-id (+ current-stream-id u1))
        (ok current-stream-id)
    )
)

;; Increase the stream balance locked in
(define-public (refuel
        (stream-id uint)
        (amount uint)
    )
    (let ((stream (unwrap! (map-get? streams stream-id) ERR_INVALID_STREAM_ID)))
        (asserts! (is-eq contract-caller (get sender stream)) ERR_UNAUTHORIZED)
        (try! (stx-transfer? amount contract-caller (as-contract tx-sender)))
        (map-set streams stream-id
            (merge stream { balance: (+ (get balance stream) amount) })
        )
        (ok amount)
    )
)

;; Withdraw received tokens
(define-public (withdraw (stream-id uint))
    (let (
            (stream (unwrap! (map-get? streams stream-id) ERR_INVALID_STREAM_ID))
            (balance (balance-of stream-id contract-caller))
        )
        (asserts! (is-eq contract-caller (get recepient stream)) ERR_UNAUTHORIZED)
        (map-set streams stream-id
            (merge stream { withdrawn-balance: (+ (get withdrawn-balance stream) balance) })
        )
        (try! (as-contract (stx-transfer? balance tx-sender (get recepient stream))))
        (ok balance)
    )
)

;; Withdraw extra tokens from the stream
(define-public (refund (stream-id uint))
    (let (
            (stream (unwrap! (map-get? streams stream-id) ERR_INVALID_STREAM_ID))
            (balance (balance-of stream-id (get sender stream)))
        )
        (asserts! (is-eq contract-caller (get sender stream)) ERR_UNAUTHORIZED)
        (asserts! (< (get end-block (get timeframe stream)) stacks-block-height)
            ERR_STREAM_STILL_ACTIVE
        )
        (map-set streams stream-id
            (merge stream { balance: (- (get balance stream) balance) })
        )
        (try! (as-contract (stx-transfer? balance tx-sender (get sender stream))))
        (ok balance)
    )
)

;; Update stream configuration
(define-public (update-details
        (stream-id uint)
        (payment-per-block uint)
        (timeframe {
            start-block: uint,
            end-block: uint,
        })
        (signature (buff 65))
        (signer principal)
    )
    (let ((stream (unwrap! (map-get? streams stream-id) ERR_INVALID_SIGNATURE)))
        (asserts!
            (validate-signature
                (hash-stream stream-id payment-per-block timeframe)
                signature signer
            )
            ERR_INVALID_SIGNATURE
        )
        (asserts!
            (or
                (and (is-eq (get sender stream) contract-caller) (is-eq (get recepient stream) signer))
                (and (is-eq (get sender stream) signer) (is-eq (get recepient stream) contract-caller))
            )
            ERR_UNAUTHORIZED
        )
        (map-set streams stream-id
            (merge stream {
                payment-per-block: payment-per-block,
                timeframe: timeframe,
            })
        )
        (ok true)
    )
)

;; read only functions
;; Calculate the number of blocks elapsed since the stream started
(define-read-only (calculate-block-delta (timeframe {
    start-block: uint,
    end-block: uint,
}))
    (let (
            (start-block (get start-block timeframe))
            (end-block (get end-block timeframe))
            (delta (if (<= stacks-block-height start-block)
                ;; then
                u0
                ;; else
                (if (< stacks-block-height end-block)
                    ;; then
                    (- stacks-block-height start-block)
                    ;; else
                    (- end-block start-block)
                )
            ))
        )
        delta
    )
)

;; Check for a balance available to withdraw for a given party
(define-read-only (balance-of
        (stream-id uint)
        (who principal)
    )
    (let (
            (stream (unwrap! (map-get? streams stream-id) u0))
            (block-delta (calculate-block-delta (get timeframe stream)))
            (recepient-balance (* block-delta (get payment-per-block stream)))
        )
        (if (is-eq who (get recepient stream))
            (- recepient-balance (get withdrawn-balance stream))
            (if (is-eq who (get sender stream))
                (- (get balance stream) recepient-balance)
                u0
            )
        )
    )
)

;; Get hash of the stream
(define-read-only (hash-stream
        (stream-id uint)
        (new-payment-per-block uint)
        (new-timeframe {
            start-block: uint,
            end-block: uint,
        })
    )
    (let (
            (stream (unwrap! (map-get? streams stream-id) (sha256 0)))
            (msg (concat
                (concat (unwrap-panic (to-consensus-buff? stream))
                    (unwrap-panic (to-consensus-buff? new-payment-per-block))
                )
                (unwrap-panic (to-consensus-buff? new-timeframe))
            ))
        )
        (sha256 msg)
    )
)

;; Signature verification
(define-read-only (validate-signature
        (hash (buff 32))
        (signature (buff 65))
        (signer principal)
    )
    (is-eq (principal-of? (unwrap! (secp256k1-recover? hash signature) false))
        (ok signer)
    )
)

;; private functions
;;
