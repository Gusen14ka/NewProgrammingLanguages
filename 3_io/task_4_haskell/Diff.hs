import Data.Array
import System.Environment (getArgs)
import System.IO

data Change = Same String | Removed String | Added String

render :: Change -> String
render (Same s)    = "  " ++ s
render (Removed s) = "- " ++ s
render (Added s)   = "+ " ++ s

diff :: [String] -> [String] -> [Change]
diff xs ys = walk 0 0
  where
    n = length xs
    m = length ys
    a = listArray (0, n - 1) xs
    b = listArray (0, m - 1) ys
    lcs = array ((0, 0), (n, m))
      [ ((i, j), cell i j) | i <- [0 .. n], j <- [0 .. m] ]
    cell i j
      | i == n || j == m = 0 :: Int
      | a ! i == b ! j   = 1 + lcs ! (i + 1, j + 1)
      | otherwise        = max (lcs ! (i + 1, j)) (lcs ! (i, j + 1))
    walk i j
      | i == n && j == m = []
      | i == n           = Added (b ! j) : walk i (j + 1)
      | j == m           = Removed (a ! i) : walk (i + 1) j
      | a ! i == b ! j   = Same (a ! i) : walk (i + 1) (j + 1)
      | lcs ! (i + 1, j) >= lcs ! (i, j + 1) = Removed (a ! i) : walk (i + 1) j
      | otherwise        = Added (b ! j) : walk i (j + 1)

main :: IO ()
main = do
  args <- getArgs
  (old, new) <- case args of
    [f1, f2] -> return (f1, f2)
    _ -> do
      putStr "First file: " >> hFlush stdout
      f1 <- getLine
      putStr "Second file: " >> hFlush stdout
      f2 <- getLine
      return (f1, f2)

  xs <- lines <$> readFile old
  ys <- lines <$> readFile new
  let changes = diff xs ys
      count p = length (filter p changes)
      added   = count (\c -> case c of Added _ -> True; _ -> False)
      removed = count (\c -> case c of Removed _ -> True; _ -> False)
      same    = count (\c -> case c of Same _ -> True; _ -> False)
      report  = unlines $
        ["--- " ++ old, "+++ " ++ new] ++ map render changes ++
        ["", "added: " ++ show added ++ ", removed: " ++ show removed ++ ", unchanged: " ++ show same]

  putStr report
  writeFile "diff_report.txt" report
  putStrLn "Report saved to diff_report.txt"
