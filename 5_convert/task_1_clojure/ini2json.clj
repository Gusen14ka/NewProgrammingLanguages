(ns ini2json
  (:require [clojure.string :as str]))

(defn index-of-key [pairs k]
  (first (keep-indexed (fn [i [kk _]] (when (= kk k) i)) pairs)))

(defn put [pairs k v]
  (if-let [i (index-of-key pairs k)]
    (assoc pairs i [k v])
    (conj pairs [k v])))

(defn parse-ini [text]
  (loop [lines (str/split-lines text)
         n 1
         section "default"
         result []]
    (if (empty? lines)
      result
      (let [line (str/trim (first lines))
            rest-lines (rest lines)]
        (cond
          (or (str/blank? line) (str/starts-with? line ";") (str/starts-with? line "#"))
          (recur rest-lines (inc n) section result)

          (and (str/starts-with? line "[") (str/ends-with? line "]"))
          (let [name (str/trim (subs line 1 (dec (count line))))]
            (recur rest-lines (inc n) name
                   (if (index-of-key result name) result (conj result [name []]))))

          (str/includes? line "=")
          (let [i (str/index-of line "=")
                k (str/trim (subs line 0 i))
                v (str/trim (subs line (inc i)))]
            (recur rest-lines (inc n) section
                   (if-let [i (index-of-key result section)]
                     (update-in result [i 1] put k v)
                     (conj result [section [[k v]]]))))

          :else
          (do (binding [*out* *err*]
                (println (str "Warning: line " n " skipped: " line)))
              (recur rest-lines (inc n) section result)))))))

(defn escape [s]
  (str/escape s {\" "\\\"" \\ "\\\\" \newline "\\n" \return "\\r" \tab "\\t"}))

(defn json-value [v]
  (cond
    (re-matches #"-?(0|[1-9]\d*)(\.\d+)?" v) v
    (#{"true" "false"} (str/lower-case v)) (str/lower-case v)
    :else (str "\"" (escape v) "\"")))

(defn to-json [sections]
  (let [pad (fn [n] (apply str (repeat n "  ")))
        entry (fn [[k v]] (str (pad 2) "\"" (escape k) "\": " (json-value v)))
        section (fn [[name kvs]]
                  (if (empty? kvs)
                    (str (pad 1) "\"" (escape name) "\": {}")
                    (str (pad 1) "\"" (escape name) "\": {\n"
                         (str/join ",\n" (map entry kvs)) "\n"
                         (pad 1) "}")))]
    (str "{\n" (str/join ",\n" (map section sections)) "\n}\n")))

(let [[in out] *command-line-args*
      in (or in "config.ini")
      out (or out (str/replace in #"\.ini$" ".json"))
      json (to-json (parse-ini (slurp in)))]
  (print json)
  (spit out json)
  (println (str "Saved to " out)))
