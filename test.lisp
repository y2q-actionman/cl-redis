;;; CL-REDIS testsuite package definition
;;; (c) Vsevolod Dyomkin, Oleksandr Manzyuk. see LICENSE file for permissions

(in-package :cl-user)

(defpackage #:redis-test
  (:use :common-lisp :rutils.user :rutils.short #+:nuts :nuts
        :redis)
  (:export #:run-tests))

(in-package #:redis-test)

(deftest tell ()
  (with-connection ()
    (let ((*echo-p* t)
          (*echo-stream* (make-string-output-stream)))
      (list
       (check string=
              (progn (tell :inline 'ping)
                     (get-output-stream-string *echo-stream*))
              "C: PING
")
       (check string=
              (progn (tell :inline 'sort "a" :start "1" :end "2")
                     (get-output-stream-string *echo-stream*))
              "C: SORT a LIMIT 1 2
")
       (check string=
              (progn (tell :bulk 'set "a" "123")
                     (get-output-stream-string *echo-stream*))
              "C: SET a 3
C: 123
"))
       (check string=
              (progn (tell :multi 'mset "a" "123" "b" "456")
                     (get-output-stream-string *echo-stream*))
              "C: *5
C: $4
C: MSET
C: $1
C: a
C: $3
C: 123
C: $1
C: b
C: $3
C: 456
"))))

(defun expect-from-str (expected input)
  (with-connection ()
    (let ((ext-fmt (redis::connection-external-format redis::*connection*)))
      (flexi-streams:with-input-from-sequence
          (in (flexi-streams:string-to-octets
               (strcat input "
")
               :external-format ext-fmt))
        (setf in
              (flexi-streams:make-flexi-stream
               in
               :external-format ext-fmt
               :element-type 'flexi-streams:octet)
              (redis::connection-stream redis::*connection*) in)
        (expect expected)))))

(deftest expect ()
  (check true            (expect-from-str :ok "+OK"))
  (check true            (expect-from-str :pong "+PONG"))
  (check string= "10$"   (expect-from-str :inline "+10$"))
  (check null            (expect-from-str :boolean "+0$"))
  (check = 10            (expect-from-str :integer "+10"))
  (check string= "abc"   (expect-from-str :bulk "+3
abc"))
  (check equal '("a" "") (expect-from-str :multi "*2
$1
a
$0
"))
  (check equal '("a" "b" "c")
                         (expect-from-str :list "+5
a b c")))

(defun find-s (seq str)
  (true (find str seq :test #'string=)))

(defun null-diff (set1 set2)
  (null (set-exclusive-or set1 set2 :test #'equal)))

(defmacro with-test-db (&body body)
  `(with-connection ()
     (cumulative-and
      (check true (red-ping))
      (check true (red-select 15))
      (check true (red-flushdb))
      ,@body
      (check true (red-flushdb)))))

(deftest commands ()
  (with-test-db
    (check true              (red-ping))
    (check true              (red-select 15)) ; select last DB index
    (check true              (red-flushdb))
    #+nil (red-quit)
    #+nil (red-auth)
    (check true              (red-set "y" "1"))
    (check true              (red-set "ігрек" "1"))
    (check string= "1"       (red-getset "y" "2"))
    (check string= "1"       (red-getset "ігрек" "2"))
    (check string= "2"       (red-get "y"))
    (check string= "2"       (red-get "ігрек"))
    (check true              (red-set "z" "3"))
    (check true              (red-set "зед" "3"))
    (check equal '("2" "3")  (red-mget "y" "z"))
    (check equal '("2" "3")  (red-mget "ігрек" "зед"))
    (check equal '("2" nil)  (red-mget "y" "a"))
    (check equal '("2" nil)  (red-mget "ігрек" "а"))
    (check null              (red-setnx "z" "3"))
    (check null              (red-setnx "зед" "3"))
    (check true              (red-setnx "u" "3"))
    (check true              (red-setnx "ю" "3"))
    (check = 4               (red-incr "u"))
    (check = 4               (red-incr "ю"))
    (check = 6               (red-incrby "u" 2))
    (check = 6               (red-incrby "ю" 2))
    (check = 5               (red-decr "u"))
    (check = 5               (red-decr "ю"))
    (check = 3               (red-decrby "u" 2))
    (check = 3               (red-decrby "ю" 2))
    (check true              (red-exists "u"))
    (check true              (red-exists "ю"))
    (check null              (red-exists "v"))
    (check null              (red-exists "ві"))
    (check true              (red-del "u"))
    (check true              (red-del "ю"))
    (check null              (red-exists "u"))
    (check null              (red-exists "ю"))
    (check string= "none"    (red-type "u"))
    (check string= "none"    (red-type "ю"))
    (check string= "string"  (red-type "z"))
    (check string= "string"  (red-type "зед"))
    (check null-diff '("y" "ігрек" "z" "зед")
                             (red-keys "*"))
    (check true              (red-rename "z" "c"))
    (check true              (red-rename "зед" "це"))
    (check string= "3"       (red-get "c"))
    (check string= "3"       (red-get "це"))
    (check null              (red-renamenx "y" "c"))
    (check null              (red-renamenx "ігрек" "це"))
    (check true              (red-renamenx "y" "b"))
    (check true              (red-renamenx "ігрек" "бе"))
    (check-errs              (red-renamenx "b" "b"))
    (check-errs              (red-renamenx "бе" "бе"))
    (check = 4               (red-dbsize))
    (check true              (red-expire "b" 1))
    (check true              (red-expire "бе" 1))
    (check null              (progn (sleep 2)
                                    (red-get "b")))
    (check null              (progn (sleep 2)
                                    (red-get "бе")))
    (check null              (red-expire "b" 1))
    (check null              (red-expire "бе" 1))
    (check find-s '("c" "це")
                             (red-randomkey))
    (check true              (red-expire "c" 600))
    (check true              (red-expire "це" 600))
    (check < 595             (red-ttl "c"))
    (check < 595             (red-ttl "це"))
    (check true              (red-mset "k1" "v1" "k2" "v2")) 
    (check true              (red-mset "ка1" "ве1" "ка2" "ве2")) 
    (check null              (red-msetnx "k1" "w1" "k3" "v3"))
    (check null              (red-msetnx "ка1" "дубльве1" "ка3" "ве3"))
    (check null              (red-exists "k3"))
    (check null              (red-exists "ка3"))
    (check true              (red-msetnx "k4" "v4" "k5" "v5"))
    (check true              (red-msetnx "ка4" "ве4" "ка5" "ве5"))
    (check equal '("v1" "v2" "v4" "v5")
                             (red-mget "k1" "k2" "k4" "k5"))
    (check equal '("ве1" "ве2" "ве4" "ве5")
                             (red-mget "ка1" "ка2" "ка4" "ка5"))
    (check true              (red-mset "k1" "w1" "k2" "v2"))
    (check true              (red-mset "ка1" "дубльве1" "ка2" "ве2"))
    (check equal "w1"        (red-get "k1"))
    (check equal "дубльве1"  (red-get "ка1"))
    #+nil (red-move)
    #+nil (red-flushall)
    (check true              (red-save))
    (check true              (red-bgsave))
    (check integerp          (red-lastsave))
    #+nil (red-shutdown)
    #+nil (red-info)
    #+nil (red-monitor)
    #+nil (red-slaveof)))

(deftest sort()
  (with-test-db
    (check true                    (red-rpush "numbers" "1"))
    (check true                    (red-rpush "числа" "1"))
    (check true                    (red-rpush "numbers" "2"))
    (check true                    (red-rpush "числа" "2"))
    (check true                    (red-rpush "numbers" "3"))
    (check true                    (red-rpush "числа" "3"))
    (check true                    (red-set "object_1" "o1"))
    (check true                    (red-set "об'єкт_1" "о1"))
    (check true                    (red-set "object_2" "o2"))
    (check true                    (red-set "об'єкт_2" "о2"))
    (check true                    (red-set "object_3" "o3"))
    (check true                    (red-set "об'єкт_3" "о3"))
    (check true                    (red-set "weight_1" "47"))
    (check true                    (red-set "вага_1" "47"))    
    (check true                    (red-set "weight_2" "13"))
    (check true                    (red-set "вага_2" "13"))    
    (check true                    (red-set "weight_3" "32"))
    (check true                    (red-set "вага_3" "32"))
    (check equal '("1" "2" "3")    (red-sort "numbers"))
    (check equal '("1" "2" "3")    (red-sort "числа"))
    (check equal '("2" "3")        (red-sort "numbers" :start 1 :end 2))
    (check equal '("2" "3")        (red-sort "числа" :start 1 :end 2))
    (check equal '("3" "2" "1")    (red-sort "numbers" :desc t))
    (check equal '("2" "1")        (red-sort "numbers" :desc t :start 1 :end 2))
    (check equal '("3" "2" "1")    (red-sort "числа" :desc t))
    (check equal '("2" "1")        (red-sort "числа" :desc t :start 1 :end 2))
    (check equal '("2" "3" "1")    (red-sort "numbers" :by "weight_*"))
    (check equal '("2" "3" "1")    (red-sort "числа" :by "вага_*"))
    (check equal '("o2" "o3" "o1") (red-sort "numbers" :by "weight_*"
                                             :get "object_*"))
    (check equal '("о2" "о3" "о1") (red-sort "числа" :by "вага_*"
                                             :get "об'єкт_*"))
    (check equal '("o1" "o3" "o2") (red-sort "numbers" :by "weight_*"
                                             :get "object_*"
                                             :desc t))
    (check equal '("о1" "о3" "о2") (red-sort "числа" :by "вага_*"
                                             :get "об'єкт_*"
                                             :desc t))))

(deftest l-commands ()
  (with-test-db
    (check true              (red-rpush "l" "1"))
    (check true              (red-rpush "ел" "1"))
    (check true              (red-rpush "l" "1"))
    (check true              (red-rpush "ел" "1"))
    (check true              (red-rpush "l" "1"))
    (check true              (red-rpush "ел" "1"))
    (check = 3               (red-lrem "l" 0 "1"))
    (check = 3               (red-lrem "ел" 0 "1"))
    (check = 0               (red-lrem "l" 0 "a"))
    (check = 0               (red-lrem "ел" 0 "а"))
    (check true              (red-lpush "l" "1"))
    (check true              (red-lpush "ел" "1"))
    (check true              (red-lpush "l" "0"))
    (check true              (red-lpush "ел" "0"))
    (check = 2               (red-llen "l"))
    (check = 2               (red-llen "ел"))
    (check equal '("0" "1")  (red-lrange "l" 0 1))
    (check equal '("0" "1")  (red-lrange "ел" 0 1))
    (check equal '("0")      (red-lrange "l" 0 0))
    (check equal '("0")      (red-lrange "ел" 0 0))
    (check equal '("0" "1")  (red-lrange "l" 0 2))
    (check equal '("0" "1")  (red-lrange "ел" 0 2))
    (check equal '("0" "1")  (red-lrange "l" 0 10))
    (check equal '("0" "1")  (red-lrange "ел" 0 10))
    (check equal '("1")      (red-lrange "l" 1 1))
    (check equal '("1")      (red-lrange "ел" 1 1))
    (check null              (red-lrange "l" 2 1))
    (check null              (red-lrange "ел" 2 1))
    (check null              (red-lrange "l" 2 3))
    (check null              (red-lrange "ел" 2 3))
    (check string= "0"       (red-lindex "l" 0))
    (check string= "0"       (red-lindex "ел" 0))
    (check true              (red-lset "l" 0 "a"))
    (check true              (red-lset "ел" 0 "а"))
    (check equal '("a" "1")  (red-lrange "l" 0 10))
    (check equal '("а" "1")  (red-lrange "ел" 0 10))
    (check true              (red-ltrim "l" 0 0))
    (check true              (red-ltrim "ел" 0 0))
    (check equal '("a")      (red-lrange "l" 0 10))
    (check equal '("а")      (red-lrange "ел" 0 10))
    (check true              (red-ltrim "l" 2 3))
    (check true              (red-ltrim "ел" 2 3))
    (check null              (red-lrange "l" 0 10))
    (check null              (red-lrange "ел" 0 10))
    (check true              (red-lpush "l" "2"))
    (check true              (red-lpush "ел" "2"))
    (check true              (red-rpush "l" "3"))
    (check true              (red-rpush "ел" "3"))
    (check true              (red-rpush "l" "4"))
    (check true              (red-rpush "ел" "4"))
    (check string= "2"       (red-lpop "l"))
    (check string= "2"       (red-lpop "ел"))
    (check string= "4"       (red-rpop "l"))
    (check string= "4"       (red-rpop "ел"))
    (check-errs              (red-get "l"))
    (check-errs              (red-get "ел"))))

(deftest s-commands ()
  (with-test-db
    (check true              (red-sadd "s" "1"))
    (check true              (red-sadd "ес" "1"))
    (check null              (red-sadd "s" "1"))
    (check null              (red-sadd "ес" "1"))
    (check true              (red-sadd "s" "2"))
    (check true              (red-sadd "ес" "2"))
    (check find-s '("2" "1") (red-spop "s"))
    (check find-s '("2" "1") (red-spop "ес"))
    (check true              (or (red-sadd "s" "2")
                                 (red-sadd "s" "1")))
    (check true              (or (red-sadd "ес" "2")
                                 (red-sadd "ес" "1")))
    (check true              (red-srem "s" "1"))
    (check true              (red-srem "ес" "1"))
    (check string= "2"       (red-spop "s"))
    (check string= "2"       (red-spop "ес"))
    (check null              (red-spop "s"))
    (check null              (red-spop "ес"))
    (check true              (red-sadd "s" "2"))
    (check true              (red-sadd "ес" "2"))
    (check true              (red-sismember "s" "2"))
    (check true              (red-sismember "ес" "2"))
    (check true              (red-sadd "s" "1"))
    (check true              (red-sadd "ес" "1"))
    (check true              (red-smove "s" "s2" "1"))
    (check true              (red-smove "ес" "ес2" "1"))
    (check true              (red-sismember "s2" "1"))
    (check true              (red-sismember "ес2" "1"))
    (check null              (red-smove "s" "s2" "3"))
    (check null              (red-smove "ес" "ес2" "3"))
    (check null              (red-sismember "s2" "3"))
    (check null              (red-sismember "ес2" "3"))
    (check true              (red-sadd "s" "1"))
    (check true              (red-sadd "ес" "1"))
    (check true              (red-smove "s" "s2" "1"))
    (check true              (red-smove "ес" "ес2" "1"))
    (check = 1               (red-scard "s"))
    (check = 1               (red-scard "ес"))
    (check null              (red-sinter "s" "s2"))
    (check null              (red-sinter "ес" "ес2"))
    (check true              (red-sadd "s" "1"))
    (check true              (red-sadd "ес" "1"))
    (check equal '("1")      (red-sinter "s" "s2"))
    (check equal '("1")      (red-sinter "ес" "ес2"))
    (check true              (red-sinterstore "s3" "s" "s2"))
    (check true              (red-sinterstore "ес3" "ес" "ес2"))
    (check equal '("1")      (red-smembers "s3"))
    (check equal '("1")      (red-smembers "ес3"))
    (check null-diff '("1" "2")
                             (red-sunion "s" "s2"))
    (check null-diff '("1" "2")
                             (red-sunion "ес" "ес2"))
    (check true              (red-sunionstore "s4" "s" "s2"))
    (check true              (red-sunionstore "ес4" "ес" "ес2"))
    (check null-diff '("1" "2")
                             (red-smembers "s4"))
    (check equal '("1" "2")  (red-smembers "ес4"))
    (check equal '("2")      (red-sdiff "s4" "s3"))
    (check equal '("2")      (red-sdiff "ес4" "ес3"))
    (check true              (red-sdiffstore "s5" "s4" "s3"))
    (check true              (red-sdiffstore "ес5" "ес4" "ес3"))
    (check equal '("2")      (red-smembers "s5"))
    (check equal '("2")      (red-smembers "ес5"))))

(deftest z-commands ()
  (with-test-db
    (check true (red-zadd "set" 1 "e1"))
    (check true (red-zadd "множина" 1 "елемент1"))
    (check true (red-zadd "set" 2 "e2"))
    (check true (red-zadd "множина" 2 "елемент2"))
    (check true (red-zadd "set" 3 "e3"))
    (check true (red-zadd "множина" 3 "елемент3"))
    (check true (red-zrem "set" "e2"))
    (check true (red-zrem "множина" "елемент2"))
    (check null (red-zrem "set" "e2"))
    (check null (red-zrem "множина" "елемент2"))
    (check true (red-zadd "set" 10 "e2"))
    (check true (red-zadd "множина" 10 "елемент2"))
    (check true (red-zadd "set" 4 "e4"))
    (check true (red-zadd "множина" 4 "елемент4"))
    (check true (red-zadd "set" 5 "e5"))
    (check true (red-zadd "множина" 5 "елемент5"))
    (check equal 5 (red-zcard "set"))
    (check equal 5 (red-zcard "множина"))
    (check equal "10" (red-zscore "set" "e2"))
    (check equal "10" (red-zscore "множина" "елемент2"))
    (check equal '("e3" "e4" "e5")  (red-zrange "set" 1 3))
    (check equal '("елемент3" "елемент4" "елемент5")  (red-zrange "множина" 1 3))
    (check equal '("e4" "e3" "e1") (red-zrevrange "set" 2 4))
    (check equal '("елемент4" "елемент3" "елемент1") (red-zrevrange "множина" 2 4))
    (check equal '("e5" "e2") (red-zrangebyscore "set" 5 10))
    (check equal '("елемент5" "елемент2") (red-zrangebyscore "множина" 5 10))
    (check equal 3 (red-zremrangebyscore "set" 2 7))
    (check equal 3 (red-zremrangebyscore "множина" 2 7))
    (check equal '("e1" "e2") (red-zrange "set" 0 -1))
    (check equal '("елемент1" "елемент2") (red-zrange "множина" 0 -1))))

(defun run-tests (&key debug)
  (let ((*echo-p* debug))
    (terpri)
    (princ "Runnning CL-REDIS tests... ")
    (princ (if (every (lambda (rez)
                        (and-it (mklist rez)
                                (every (lambda (rez) (eq t rez))
                                       it)))
                      (run-test tell
                                expect
                                commands
                                sort
                                l-commands
                                s-commands
                                z-commands))
               "OK"
               (format nil "some tests failed. See log file for details: ~a"
                       *log-out*)))
    (terpri)
    (terpri)
    (values)))
      

;;; end