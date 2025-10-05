;; title: stream
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;; error codes
(define-constant ERR_UNAUTHORIZED (err u0))
(define-constant ERR_INVALID_SIGNATURE (err u1))
(define-constant ERR_STREAM_STILL_ACTIVE (err u2))
(define-constant ERR_INVALID_STREAM_ID (err u3))

;; data vars
(define-data-var latest-stream-id uint u0)

;; data maps
;; streams mapping
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
;;

;; read only functions
;;

;; private functions
;;
