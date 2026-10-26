fun prefixFunction(pattern: String): IntArray {
    val pi = IntArray(pattern.length)
    var k = 0
    for (i in 1 until pattern.length) {
        while (k > 0 && pattern[i] != pattern[k]) k = pi[k - 1]
        if (pattern[i] == pattern[k]) k++
        pi[i] = k
    }
    return pi
}

fun kmpSearch(text: String, pattern: String): Pair<List<Int>, Long> {
    val pi = prefixFunction(pattern)
    val found = mutableListOf<Int>()
    var comparisons = 0L
    var k = 0
    for (i in text.indices) {
        while (true) {
            comparisons++
            if (text[i] == pattern[k]) {
                k++
                break
            }
            if (k == 0) break
            k = pi[k - 1]
        }
        if (k == pattern.length) {
            found += i - pattern.length + 1
            k = pi[k - 1]
        }
    }
    return found to comparisons
}

fun naiveSearch(text: String, pattern: String): Pair<List<Int>, Long> {
    val found = mutableListOf<Int>()
    var comparisons = 0L
    for (start in 0..text.length - pattern.length) {
        var j = 0
        while (j < pattern.length) {
            comparisons++
            if (text[start + j] != pattern[j]) break
            j++
        }
        if (j == pattern.length) found += start
    }
    return found to comparisons
}

fun main(args: Array<String>) {
    val text: String
    val pattern: String
    if (args.firstOrNull() == "demo") {
        text = "a".repeat(100_000) + "b"
        pattern = "a".repeat(50) + "b"
        println("Demo: text = 100000 x 'a' + 'b', pattern = 50 x 'a' + 'b'")
    } else if (args.size >= 2) {
        text = args[0]
        pattern = args[1]
    } else {
        print("Text: ")
        text = readLine().orEmpty()
        print("Pattern: ")
        pattern = readLine().orEmpty()
    }
    if (pattern == "" || pattern.length > text.length) {
        println("Pattern must be non-empty and not longer than the text")
        return
    }

    if (pattern.length <= 30) println("Prefix function: ${prefixFunction(pattern).joinToString(" ")}")

    val (kmpFound, kmpCmp) = kmpSearch(text, pattern)
    val (naiveFound, naiveCmp) = naiveSearch(text, pattern)

    println("Found at positions: ${if (kmpFound.isEmpty()) "none" else kmpFound.joinToString(", ")}")
    println("KMP comparisons:   $kmpCmp")
    println("Naive comparisons: $naiveCmp")
    println("Results equal: ${kmpFound == naiveFound}")
}
