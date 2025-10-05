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

;; private functions
;;
