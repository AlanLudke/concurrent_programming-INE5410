package org.example.ine5410;

import javax.annotation.Nonnull;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.*;

public class MergeSortExecutor<T extends Comparable<T>> implements MergeSort<T> {
    @Nonnull
    @Override
    public ArrayList<T> sort(@Nonnull List<T> list) {
        ExecutorService executor = Executors.newCachedThreadPool();
        ArrayList<T> result = sort(executor, list);
        executor.shutdown();
        try {
            executor.awaitTermination(Long.MAX_VALUE, TimeUnit.SECONDS);
        } catch (InterruptedException e) {
            System.err.println("Aborting wait for executor shutdown due to InterruptedException");
        }
        return result;

    }

    @Nonnull
    private ArrayList<T> sort(final ExecutorService executor, @Nonnull final List<T> list) {
        if (list.size() <= 8192)
            return new MergeSortSerial<T>().sort(list);

        final int mid = list.size() / 2;

        Future<ArrayList<T>> leftFuture;
        leftFuture = executor.submit(new Callable<ArrayList<T>>() {
            @Override
            public ArrayList<T> call() {
                return MergeSortExecutor.this.sort(executor, list.subList(0, mid));
            }
        });
        ArrayList<T> right = sort(executor, list.subList(mid, list.size()));


        try {
            return MergeSortHelper.merge(leftFuture.get(), right);
        } catch (InterruptedException | ExecutionException e) {
            if (e.getCause() != null && e.getCause() instanceof RuntimeException
                                     && e.getCause().getCause() instanceof ExecutionException) {
                throw (RuntimeException) e.getCause();
            }
            throw new RuntimeException(e);
        }
    }
}
