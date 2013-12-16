;;; Tests for bbdb-vcard.el
;;
;; Before proceeding, you should probably save your production bbdb file.
;;
;; To run the tests, eval this file.
;; In case of failure, find test results in buffer `bbdb-vcard-test-result'.
;;
;; For the sake of minimality, not all test cases are rfc compliant.

(require 'bbdb-vcard)
(require 'cl-lib)
(require 'ert)


 (defvar bbdb-vcard-test-fields
  '(firstname lastname affix aka organization phone address mail xfields)
  "BBDB record fields to check")

(defvar bbdb-vcard-xfield-ignore
  '(creation-date timestamp)
  "xfields to ignore")

(defun bbdb-vcard-record-equal (r1 r2)
  "Tests whether two BBDB records have equal components"
  (let ((fields bbdb-vcard-test-fields)
        (field-index 0))
    (while (< field-index (length fields))
      (let* ((field (nth field-index fields))
             (v1 (if (equal field 'xfields)
                     (bbdb-vcard-normalize-xfields (bbdb-record-field r1 field))
                   (bbdb-record-field r1 field)))
             (v2 (if (eq field 'xfields)
                     (bbdb-vcard-normalize-xfields (bbdb-record-field r2 field))
                   (bbdb-record-field r2 field))))
        (should (equal v1 v2)))
      (setf field-index (+ 1 field-index)))))

(defun bbdb-vcard-test
  (vcard bbdb-entry search-name
         &optional search-org search-net check-export)
  "Import VCARD and search for it in bbdb by SEARCH-NAME,
SEARCH-ORG, (perhaps later) SEARCH-NET. Perform assert checks."
  (bbdb-vcard-iterate-vcards 'bbdb-vcard-import-vcard vcard)
  (let* ((search-org (or search-org ""))
         (bbdb-search-result
          (car (bbdb-search (bbdb-search (bbdb-records) search-name)
                            nil search-org)))
         (fields bbdb-vcard-test-fields)
         (export-temp-file (expand-file-name
                            (make-temp-name "bbdb-vcard-export-test")
                            temporary-file-directory))
         (field-index 0))
    (while (< field-index (length fields))
      (let* ((field (nth field-index fields))
             (value (let ((value (bbdb-record-field bbdb-search-result field)))
                      (if (equal field 'xfields)
                          (bbdb-vcard-normalize-xfields (copy-alist value))
                        value)))
             (expected (let ((value (aref bbdb-entry field-index)))
                         (if (equal field 'xfields)
                             (bbdb-vcard-normalize-xfields (copy-alist value))
                           value))))
        (should (equal value expected))
        (setf field-index (+ 1 field-index))))
    ;; IMPORT/EXPORT test
    ;; export record as vcard and import it again
    ;; both records should match
    (when check-export
      (let* ((r1 bbdb-search-result)
             (r2 (progn
                   (bbdb-save)
                   (delete-file (buffer-file-name bbdb-buffer))
                   (kill-buffer bbdb-buffer)
                   (with-temp-buffer
                     (insert (bbdb-vcard-from r1))
                     (bbdb-vcard-import-buffer (current-buffer))
                     (car (bbdb-search (bbdb-records) ""))))))
        (bbdb-vcard-record-equal r1 r2)))))


(defmacro bbdb-vcard-test-fixture (body)
  "Creates a fixture for bbdb-vcard tests"
  (declare (debug (form)))
  `(let ((saved-bbdb-file bbdb-file)
         (bbdb-buffer-live (buffer-live-p bbdb-buffer))
         (bbdb-allow-duplicates t))
     (unwind-protect
         (progn
           ;; SETUP
           ;; setup state for tests
           (let ((temp-file (expand-file-name
                             (make-temp-name "bbdb-vcard-test")
                             temporary-file-directory)))
             (when (buffer-live-p bbdb-buffer)
               (bbdb-save)
               (kill-buffer bbdb-buffer))
             (setq bbdb-file temp-file)
             (setq bbdb-allow-duplicates t))
           ;; BODY
           ,body)
       ;; TEARDOWN
       ;; kill `bbdb-buffer' and delete `bbdb-file'
       (when (buffer-live-p bbdb-buffer)
         (with-current-buffer bbdb-buffer
           (bbdb-save)
           (kill-buffer)))
       (when (file-exists-p bbdb-file)
         (delete-file bbdb-file))
       ;; If there was an existing `bbdb-buffer' before the test, reopen it
       (setq bbdb-file saved-bbdb-file)
       (when bbdb-buffer-live
         (bury-buffer (bbdb-buffer))))))

(defun bbdb-vcard-normalize-xfields (xfields)
  "Sort a BBDB xfields field and delete the timestamps in order to make them
comparable after re-import."
  (let ((xfields (remove-alist 'xfields 'timestamp)))
    (setq xfields (remove-alist 'xfields 'creation-date))
    (sort
     xfields
     #'(lambda (x y) (if (string= (symbol-name (car x)) (symbol-name (car y)))
                        (string< (cdr x) (cdr y))
                      (string< (symbol-name (car x)) (symbol-name (car y))))))))


(ert-deftest bbdb-vcard-test-sniff-mime-type ()
  "Test MIME-type sniffing"
  (should (equal (bbdb-vcard-sniff-mime-type "Plain Text")
                 "text/plain"))
  (should (equal (bbdb-vcard-sniff-mime-type "")
                 "application/x-empty"))
  (should (equal (bbdb-vcard-sniff-mime-type
                  (base64-decode-string "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAKElEQVQoz2P8//8/AymAiYFEANWw19aWSA2M9HLSqAa6asBMAYMwpgFt4guDkeJQ1gAAAABJRU5ErkJggg=="))
                 "image/png")))

(ert-deftest bbdb-vcard-test-import-inline-media ()
  "Test media import"
  (let* ((bbdb-vcard-directory (format "/tmp/%s/" (make-temp-name "bbdb-vcard-")))
         (bbdb-media-directory "media/")
         (data "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAKElEQVQoz2P8//8/AymAiYFEANWw19aWSA2M9HLSqAa6asBMAYMwpgFt4guDkeJQ1gAAAABJRU5ErkJggg==")
         (result-filename (format "media/image-%s.png"
                                  (sha1 (base64-decode-string data))))
         (vcard-media-with-type `(("value" . ,data) ("type" . "png") ("encoding" . "b")))
         (vcard-media-no-type `(("value" . ,data) ("encoding" . "b"))))
    (unwind-protect
        (progn
          ;; with type
          (should (equal
                   (bbdb-vcard-import-inline-media vcard-media-with-type)
                   result-filename))
          (should (file-exists-p (concat bbdb-vcard-directory result-filename)))
          ;; delete imported file
          (condition-case nil
              (delete-file (concat bbdb-vcard-directory result-filename))
            (error nil))
          ;; no type
          (should (equal
                   (bbdb-vcard-import-inline-media vcard-media-no-type)
                   result-filename))
          (should (file-exists-p (concat bbdb-vcard-directory result-filename))))
      (condition-case nil
          (delete-directory bbdb-vcard-directory t)
        (error nil)))))

(ert-deftest bbdb-vcard-test-unvcardize-name ()
  (should
   (equal (bbdb-vcard-unvcardize-name
           '("Smitts" "Lucy" ("Kate" "Mary") "Dr." ("PhD" "Esq")))
          '("Lucy Kate Mary" "Smitts" ("Dr." "PhD" "Esq"))))
  (should
   (equal (bbdb-vcard-unvcardize-name
           '("Smitts" "Lucy" nil "Dr." nil))
          '("Lucy" "Smitts" ("Dr."))))
  (should
   (equal (bbdb-vcard-unvcardize-name
           '(nil "Lucy" nil nil nil))
          '("Lucy" nil nil)))
  (should
   (equal (bbdb-vcard-unvcardize-name
           "Lucy Smitts")
          '("Lucy" "Smitts" nil))))

(ert-deftest bbdb-vcard-test-unvcardize-org ()
  (should
   (equal (bbdb-vcard-unvcardize-org
           '("Foo" "Bar" "Baz"))
          "Foo\nBar\nBaz"))
  (should
   (equal (bbdb-vcard-unvcardize-org
           "Foo Bar Baz")
          "Foo Bar Baz")))

(ert-deftest bbdb-vcard-test-unvcardize-adr ()
  (should
   (equal (bbdb-vcard-unvcardize-adr
           '(("type" "home")
             ("content"
              (nil nil "123 Main Street" "Any Town" "CA" "91921-1234" "USA"))))
          ["Home" "123 Main Street" "Any Town" "CA" "91921-1234" "USA"]))
  (should
   (equal (bbdb-vcard-unvcardize-adr
           '(("type" "home")
             ("content"
              (nil nil ("Apt. 81" "8th Floor" "123 Main Street")
               "Any Town" "CA" "91921-1234" "USA"))))
          ["Home" "Apt. 81\n8th Floor\n123 Main Street"
           "Any Town" "CA" "91921-1234" "USA"])))

(ert-deftest bbdb-vcard-test-elements-of-type ()
  (with-temp-buffer
    (insert "
BEGIN:VCARD
N:Smith;John;;;PhD
EMAIL;type=INTERNET;type=HOME:fredo@gmail.com
KEY;TYPE=png;ENCODING=b:MIICajCCAdOgAwBhMCVVMxLDAqBgdljYX==
END:VCARD")
  (should
   (equal
    (bbdb-vcard-elements-of-type "KEY" nil nil)
    '((("encoding" . "b")
      ("type" . "png")
      ("content" . "MIICajCCAdOgAwBhMCVVMxLDAqBgdljYX==")))))
  (should
   (equal
    (bbdb-vcard-elements-of-type "N" t t)
    '((("content" . ("Smith" "John" nil nil "PhD"))))))))


(ert-deftest bbdb-vcard-test-scardize ()
  (should
   (equal (bbdb-vcard-scardize
           (bbdb-vcard-unfold-lines
"
BEGIN:VCARD
VERSION:3.0
FN:Mr. John Q. Public\\, Esq.
N:Stevenson;John;Philip,Paul;Dr.;Jr.,M.D.,A.C.P.
NICKNAME:Robbie
PHOTO;VALUE=uri:http://www.abc.com/pub/photos
 /jqpublic.gif
BDAY:1996-04-15
ADR;TYPE=dom,home,postal,parcel:;;123 Main
  Street;Any Town;CA;91921-1234
LABEL;TYPE=dom,home,postal,parcel:Mr.John Q. Public\\, Esq.\\n
 Mail Drop: TNE QB\\n123 Main Street\\nAny Town\\, CA  91921-1234
 \\nU.S.A.
TEL;TYPE=work,voice,pref,msg:+1-213-555-1234
EMAIL;TYPE=internet:jqpublic@xyz.dom1.com
EMAIL;TYPE=internet:jdoe@isp.net
TITLE:Director\\, Research and Development
ROLE:Programmer
AGENT;VALUE=uri:
 CID:JQPUBLIC.part3.960129T083020.xyzMail@host3.com
ORG:ABC\\, Inc.;North American Division;Marketing
CATEGORIES:TRAVEL AGENT
NOTE:This fax number is operational 0800 to 1715
  EST\\, Mon-Fri.
PRODID:-//ONLINE DIRECTORY//NONSGML Version 1//EN
REV:1995-10-31T22:27:10Z
SOUND;TYPE=BASIC;ENCODING=b:MIICajCCAdOgAwIBAgICBEUwDQYJKoZIhvcN
 AQEEBQAwdzELMAkGA1UEBhMCVVMxLDAqBgNVBAoTI05ldHNjYXBlIENvbW11bm
 ljYXRpb25zIENvcnBvcmF0aW9uMRwwGgYDVQQLExNJbmZvcm1hdGlvbiBTeX==
UID:19950401-080045-40000F192713-0052
URL:http://www.swbyps.restaurant.french/~chezchic.html
END:VCARD"))
'(("FN"
  ((("content" "Mr. John Q. Public, Esq."))))
 ("N"
  ((("content"
     ("Stevenson" "John"
      ("Philip" "Paul")
      "Dr."
      ("Jr." "M.D." "A.C.P."))))))
 ("NICKNAME"
  ((("content" "Robbie"))))
 ("ORG"
  ((("content"
     ("ABC, Inc." "North American Division" "Marketing")))))
 ("EMAIL"
  ((("type" "internet")
    ("content" "jqpublic@xyz.dom1.com"))
   (("type" "internet")
    ("content" "jdoe@isp.net"))))
 ("TEL"
  ((("type" "work,voice,pref,msg")
    ("content" "+1-213-555-1234"))))
 ("ADR"
  ((("type"
     ("dom" "home" "postal" "parcel"))
    ("content"
     (nil nil "123 Main Street" "Any Town" "CA" "91921-1234")))))
 ("URL"
  ((("content" "http://www.swbyps.restaurant.french/~chezchic.html"))))
 ("NOTE"
  ((("content" "This fax number is operational 0800 to 1715 EST, Mon-Fri."))))
 ("BDAY"
  ((("content" "1996-04-15"))))
 ("CATEGORIES"
  ((("content" "TRAVEL AGENT"))))
 ("PHOTO"
  ((("value" "uri")
    ("content" "//www.abc.com/pub/photos/jqpublic.gif"))))
 ("SOUND"
  ((("encoding" "b")
    ("type" "basic")
    ("content" "MIICajCCAdOgAwIBAgICBEUwDQYJKoZIhvcNAQEEBQAwdzELMAkGA1UEBhMCVVMxLDAqBgNVBAoTI05ldHNjYXBlIENvbW11bmljYXRpb25zIENvcnBvcmF0aW9uMRwwGgYDVQQLExNJbmZvcm1hdGlvbiBTeX=="))))))))

;;;; The Import Tests
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(ert-deftest bbdb-vcard-test-rfc2426 ()
  "The following is made of examples from rfc2426."
  (bbdb-vcard-test-fixture
   (bbdb-vcard-test "
BEGIN:VCARD
VERSION:3.0
FN:Mr. John Q. Public\\, Esq.
N:Stevenson;John;Philip,Paul;Dr.;Jr.,M.D.,A.C.P.
NICKNAME:Robbie
PHOTO;VALUE=uri:http://www.abc.com/pub/photos
 /jqpublic.gif
BDAY:1996-04-15
ADR;TYPE=dom,home,postal,parcel:;;123 Main
  Street;Any Town;CA;91921-1234
LABEL;TYPE=dom,home,postal,parcel:Mr.John Q. Public\\, Esq.\\n
 Mail Drop: TNE QB\\n123 Main Street\\nAny Town\\, CA  91921-1234
 \\nU.S.A.
TEL;TYPE=work,voice,pref,msg:+1-213-555-1234
EMAIL;TYPE=internet:jqpublic@xyz.dom1.com
EMAIL;TYPE=internet:jdoe@isp.net
MAILER:PigeonMail 2.1
TZ:-05:00
GEO:37.386013;-122.082932
TITLE:Director\\, Research and Development
ROLE:Programmer
LOGO;ENCODING=b;TYPE=JPEG:MIICajCCAdOgAwIBAgICBEUwDQYJKoZIhvcN
 AQEEBQAwdzELMAkGA1UEBhMCVVMxLDAqBgNVBAoTI05ldHNjYXBlIENvbW11bm
 ljYXRpb25zIENvcnBvcmF0aW9uMRwwGgYDVQQLExNJbmZvcm1hdGlvbiBTeXN0
AGENT;VALUE=uri:
 CID:JQPUBLIC.part3.960129T083020.xyzMail@host3.com
ORG:ABC\\, Inc.;North American Division;Marketing
CATEGORIES:TRAVEL AGENT
NOTE:This fax number is operational 0800 to 1715
  EST\\, Mon-Fri.
PRODID:-//ONLINE DIRECTORY//NONSGML Version 1//EN
REV:1995-10-31T22:27:10Z
SOUND;TYPE=BASIC;ENCODING=b:MIICajCCAdOgAwIBAgICBEUwDQYJKoZIhvcN
 AQEEBQAwdzELMAkGA1UEBhMCVVMxLDAqBgNVBAoTI05ldHNjYXBlIENvbW11bm
 ljYXRpb25zIENvcnBvcmF0aW9uMRwwGgYDVQQLExNJbmZvcm1hdGlvbiBTeXN0
UID:19950401-080045-40000F192713-0052
URL:http://www.swbyps.restaurant.french/~chezchic.html
CLASS:PUBLIC
KEY;ENCODING=b:MIICajCCAdOgAwIBAgICBEUwDQYJKoZIhvcNAQEEBQA
 wdzELMAkGA1UEBhMCVVMxLDAqBgNVBAoTI05ldHNjYXBlIENbW11bmljYX
 Rpb25zIENvcnBvcmF0aW9uMRwwGgYDVQQLExNJbmZvcm1hdGlvbiBTeXN0
 ZW1zMRwwGgYDVQQDExNyb290Y2EubmV0c2NhcGUuY29tMB4XDTk3MDYwNj
 E5NDc1OVoXDTk3MTIwMzE5NDc1OVowgYkxCzAJBgNVBAYTAlVTMSYwJAYD
 VQQKEx1OZXRzY2FwZSBDb21tdW5pY2F0aW9ucyBDb3JwLjEYMBYGA1UEAx
 MPVGltb3RoeSBBIEhvd2VzMSEwHwYJKoZIhvcNAQkBFhJob3dlc0BuZXRz
 Y2FwZS5jb20xFTATBgoJkiaJk/IsZAEBEwVob3dlczBcMA0GCSqGSIb3DQ
 EBAQUAA0sAMEgCQQC0JZf6wkg8pLMXHHCUvMfL5H6zjSk4vTTXZpYyrdN2
 dXcoX49LKiOmgeJSzoiFKHtLOIboyludF90CgqcxtwKnAgMBAAGjNjA0MB
 EGCWCGSAGG+EIBAQQEAwIAoDAfBgNVHSMEGDAWgBT84FToB/GV3jr3mcau
 +hUMbsQukjANBgkqhkiG9w0BAQQFAAOBgQBexv7o7mi3PLXadkmNP9LcIP
 mx93HGp0Kgyx1jIVMyNgsemeAwBM+MSlhMfcpbTrONwNjZYW8vJDSoi//y
 rZlVt9bJbs7MNYZVsyF1unsqaln4/vy6Uawfg8VUMk1U7jt8LYpo4YULU7
 UZHPYVUaSgVttImOHZIKi4hlPXBOhcUQ==
END:VCARD
"
 ["John Philip Paul" "Stevenson"
  ("Dr." "Jr." "M.D." "A.C.P.")
  ("Robbie")
  ("ABC, Inc.
North American Division
Marketing")
  (["Office" "+1-213-555-1234"])
  (["Home"
    ("123 Main Street")
    "Any Town"
    "CA"
    "91921-1234"
    ""])
  ("jqpublic@xyz.dom1.com" "jdoe@isp.net")
  ((gpg-key-filename . "MIICajCCAdOgAwIBAgICBEUwDQYJKoZIhvcNAQEEBQAwdzELMAkGA1UEBhMCVVMxLDAqBgNVBAoTI05ldHNjYXBlIENbW11bmljYXRpb25zIENvcnBvcmF0aW9uMRwwGgYDVQQLExNJbmZvcm1hdGlvbiBTeXN0ZW1zMRwwGgYDVQQDExNyb290Y2EubmV0c2NhcGUuY29tMB4XDTk3MDYwNjE5NDc1OVoXDTk3MTIwMzE5NDc1OVowgYkxCzAJBgNVBAYTAlVTMSYwJAYDVQQKEx1OZXRzY2FwZSBDb21tdW5pY2F0aW9ucyBDb3JwLjEYMBYGA1UEAxMPVGltb3RoeSBBIEhvd2VzMSEwHwYJKoZIhvcNAQkBFhJob3dlc0BuZXRzY2FwZS5jb20xFTATBgoJkiaJk/IsZAEBEwVob3dlczBcMA0GCSqGSIb3DQEBAQUAA0sAMEgCQQC0JZf6wkg8pLMXHHCUvMfL5H6zjSk4vTTXZpYyrdN2dXcoX49LKiOmgeJSzoiFKHtLOIboyludF90CgqcxtwKnAgMBAAGjNjA0MBEGCWCGSAGG+EIBAQQEAwIAoDAfBgNVHSMEGDAWgBT84FToB/GV3jr3mcau+hUMbsQukjANBgkqhkiG9w0BAQQFAAOBgQBexv7o7mi3PLXadkmNP9LcIPmx93HGp0Kgyx1jIVMyNgsemeAwBM+MSlhMfcpbTrONwNjZYW8vJDSoi//yrZlVt9bJbs7MNYZVsyF1unsqaln4/vy6Uawfg8VUMk1U7jt8LYpo4YULU7UZHPYVUaSgVttImOHZIKi4hlPXBOhcUQ==")
   (uid . "19950401-080045-40000F192713-0052")
   (sound-filename . "MIICajCCAdOgAwIBAgICBEUwDQYJKoZIhvcNAQEEBQAwdzELMAkGA1UEBhMCVVMxLDAqBgNVBAoTI05ldHNjYXBlIENvbW11bmljYXRpb25zIENvcnBvcmF0aW9uMRwwGgYDVQQLExNJbmZvcm1hdGlvbiBTeXN0")
   (image-uri . "http://www.abc.com/pub/photos/jqpublic.gif")
   (mail-alias . "TRAVEL AGENT")
   (anniversary . "1996-04-15")
   (notes . "This fax number is operational 0800 to 1715 EST, Mon-Fri.")
   (url . "http://www.swbyps.restaurant.french/~chezchic.html"))]
 "John"
 nil nil t)))



(ert-deftest bbdb-vcard-test-no-type-params ()
  "A vcard without any type parameters."
  (bbdb-vcard-test-fixture
   (bbdb-vcard-test "
BEGIN:VCARD
VERSION:3.0
FN:First1 Last1
N:Last1;First1
NICKNAME:Firsty1
PHOTO:The Alphabet:
 abcdefghijklmnop
 qrstuvwsyz
BDAY:1999-12-05
ADR:Box111;Room 111;First Street,First Corner;Cityone;First State;11111;Country
LABEL:Label 1
TEL:+11111111
EMAIL:first1@provider1
MAILER:Wanderlust1
TZ:+01:00
GEO:37.386013;-122.082932
TITLE:Director\\, Research and Development
ROLE:Programmer
LOGO:encoded logo #1
AGENT:CID:JQPUBLIC.part3.960129T083020.xyzMail@host3.com
ORG:Company1;Unit1;Subunit1
CATEGORIES:category1
NOTE:This vcard uses every type defined in rfc2426.
PRODID:-//ONLINE DIRECTORY//NONSGML Version 1//EN
REV:1995-10-31T22:27:10Z
SORT-STRING:aaa000
SOUND:Audible1
UID:111-111-111-111
URL:http://first1.host1.org
CLASS:CONFIDENTIAL
KEY:The Key No 1
X-foo:extended type 1
END:VCARD
"
 ["First1" "Last1"
  nil
  ("Firsty1")
  ("Company1
Unit1
Subunit1")
  (["Office" "+11111111"])
  (["Office"
    ("Box111" "Room 111" "First Street" "First Corner")
    "Cityone"
    "First State"
    "11111"
    "Country"])
  ("first1@provider1")
  ((x-foo . "extended type 1")
   (gpg-key-uri . "The Key No 1")
   (class . "CONFIDENTIAL")
   (uid . "111-111-111-111")
   (sound-uri . "Audible1")
   (sort-string . "aaa000")
   (prodid . "-//ONLINE DIRECTORY//NONSGML Version 1//EN")
   (agent . "CID:JQPUBLIC.part3.960129T083020.xyzMail@host3.com")
   (logo . "encoded logo #1")
   (role . "Programmer")
   (title . "Director, Research and Development")
   (geo . "37.386013;-122.082932")
   (tz . "+01:00")
   (mailer . "Wanderlust1")
   (label . "Label 1")
   (image-uri . "The Alphabet:abcdefghijklmnopqrstuvwsyz")
   (mail-alias . "category1")
   (birthday . "1999-12-05")
   (notes . "This vcard uses every type defined in rfc2426.")
   (url . "http://first1.host1.org"))]
 "First1 Last1"
 nil nil t)))


(ert-deftest bbdb-vcard-test-bad-1 ()
  "Semi-colons where they don't belong"
  (bbdb-vcard-test-fixture
   (bbdb-vcard-test "
BEGIN:VCARD
VERSION:3.0
FN:First2; Last2
N:Last2;First2
NICKNAME:Firsty2,or; something
PHOTO:The Alphabet:
 abcdefghij;klmnop
 qrstuvwsyz
BDAY:1999-12-05
ADR:Box111;Room 111;First Street,First Corner;Cityone;First State;11111;Country
LABEL:Label 1;Label 2
TEL:+11111111;+222222
EMAIL:first1@provider1
MAILER:Wanderlust1;Wanderlust2
TZ:+01:00;Here
GEO:37.386013;-122.082932
TITLE:Director\\, Research; and Development
ROLE:Programmer
LOGO:encoded logo #1
AGENT:CID:JQPUBLIC.part3.960129T083020.xyzMail@host3.com
ORG:Company1;Unit1;Subunit1
CATEGORIES:category1
NOTE:This isn't a decent vCard. It shouldn't render our bbdb unusable. We don't expect it to re-import unchanged, though.
REV:1995-10-31T22:27:10Z
SORT-STRING:aaa000
SOUND:Audible1
UID:111-111-111-111
URL:http://first1.host1.org; My home
CLASS:CONFIDENTIAL
KEY:The Key No 1
X-foo:extended type 1
END:VCARD
"
 ["First2" "Last2"
  nil
  ("First2; Last2" "Firsty2" "or; something")
  ("Company1
Unit1
Subunit1")
  (["Office" "+11111111;+222222"])
  (["Office" ("Box111" "Room 111" "First Street" "First Corner") "Cityone" "First State" "11111" "Country"])
  ("first1@provider1")
  ((x-foo . "extended type 1")
   (gpg-key-uri . "The Key No 1")
   (class . "CONFIDENTIAL")
   (uid . "111-111-111-111")
   (sound-uri . "Audible1")
   (sort-string . "aaa000")
   (agent . "CID:JQPUBLIC.part3.960129T083020.xyzMail@host3.com")
   (logo . "encoded logo #1")
   (role . "Programmer")
   (title . "Director, Research; and Development")
   (geo . "37.386013;-122.082932")
   (tz . "+01:00;Here")
   (mailer . "Wanderlust1;Wanderlust2")
   (label . "Label 1;Label 2")
   (image-uri . "The Alphabet:abcdefghij;klmnopqrstuvwsyz")
   (mail-alias . "category1")
   (birthday . "1999-12-05")
   (notes . "This isn't a decent vCard. It shouldn't render our bbdb unusable. We don't expect it to re-import unchanged, though.")
   (url . "http://first1.host1.org; My home"))]
  "First2 Last2"
 nil nil)))
