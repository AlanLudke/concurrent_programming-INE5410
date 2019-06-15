package br.ufsc.atividade10;

import org.junit.Assert;
import org.junit.Test;

import javax.annotation.Nonnull;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import static br.ufsc.atividade10.Piece.Type.*;

public class BufferTest {
    private static final int TIMEOUT = 200;

    private boolean blocks(@Nonnull final Runnable runnable)
            throws InterruptedException {
        final boolean returned[] = {false};
        Thread thread = new Thread(new Runnable() {
            @Override
            public void run() {
                runnable.run();
                returned[0] = true;
            }
        });
        thread.start();

        Thread.sleep(BufferTest.TIMEOUT);
        boolean fail = returned[0];
        thread.interrupt();
        thread.join();

        return !fail;
    }

    private boolean takeBlocks(@Nonnull final Buffer buffer) throws InterruptedException {
        final List<Piece> os = new ArrayList<>(), xs = new ArrayList<>();
        return blocks(new Runnable() {
            @Override
            public void run() {
                try {
                    buffer.takeOXO(xs, os);
                } catch (InterruptedException ignored) {}
            }
        });
    }

    private boolean addBlocks(@Nonnull final Buffer buffer,
                              @Nonnull final Piece piece) throws InterruptedException {
        final List<Piece> os = new ArrayList<>(), xs = new ArrayList<>();
        return blocks(new Runnable() {
            @Override
            public void run() {
                try {
                    buffer.add(piece);
                } catch (InterruptedException ignored) {}
            }
        });
    }

    @Test(timeout = 1000)
    public void testWellBehaved() throws InterruptedException {
        final Buffer buffer = new Buffer(10);
        buffer.add(new Piece(1, O));
        buffer.add(new Piece(2, X));
        buffer.add(new Piece(3, O));

        final List<Piece> os = new ArrayList<>(), xs = new ArrayList<>();
        buffer.takeOXO(xs, os);

        List<Piece> expectedO = Arrays.asList(new Piece(1, O), new Piece(3, O)),
                    expectedX = Collections.singletonList(new Piece(2, X));
        Assert.assertEquals(expectedO, os);
        Assert.assertEquals(expectedX, xs);

        Assert.assertTrue("Segundo takeOXO() retornou quando deveria " +
                "bloquear para sempre", takeBlocks(buffer));
    }

    @Test(timeout = 1000 + TIMEOUT)
    public void testBlockOnEmpty() throws InterruptedException {
        Buffer buffer = new Buffer(10);
        Assert.assertTrue(takeBlocks(buffer));
    }

    @Test(timeout = 1000 + TIMEOUT*2)
    public void testBlockWithPartial() throws InterruptedException {
        Buffer buffer = new Buffer(10);
        buffer.add(new Piece(1, O));
        Assert.assertTrue(takeBlocks(buffer));
        buffer.add(new Piece(2, X));
        Assert.assertTrue(takeBlocks(buffer));
    }

    @Test(timeout = 1000 + TIMEOUT)
    public void testAddBlocks() throws InterruptedException {
        Buffer buffer = new Buffer(3);
        buffer.add(new Piece(1, O));
        buffer.add(new Piece(2, X));
        buffer.add(new Piece(3, O));

        Assert.assertTrue(addBlocks(buffer, new Piece(4, O)));
    }

    @Test(timeout = 1000 + TIMEOUT*2)
    public void testAddXBlocks() throws InterruptedException {
        Buffer buffer = new Buffer(4);
        buffer.add(new Piece(1, X));
        buffer.add(new Piece(2, X));

        Assert.assertTrue(addBlocks(buffer, new Piece(3, X)));

        buffer.add(new Piece(4, O)); //no timeout
        buffer.add(new Piece(5, O)); //no timeout

        List<Piece> xs = new ArrayList<>(), os = new ArrayList<>();
        buffer.takeOXO(xs, os);
        //queue state: X

        buffer.add(new Piece(6, X)); //no timeout

        Assert.assertTrue(addBlocks(buffer, new Piece(7, X)));
    }

    @Test(timeout = 2000)
    public void testAddOBlocks() throws InterruptedException {
        Buffer buffer = new Buffer(4);
        buffer.add(new Piece(1, O));
        buffer.add(new Piece(2, O));
        buffer.add(new Piece(3, O));

        Assert.assertTrue(addBlocks(buffer, new Piece(4, O)));

        buffer.add(new Piece(5, X)); //no timeout

        List<Piece> xs = new ArrayList<>(), os = new ArrayList<>();
        buffer.takeOXO(xs, os);
        //buffer state: O

        buffer.add(new Piece(6, O)); //no timeout
        buffer.add(new Piece(7, O)); //no timeout

        Assert.assertTrue(addBlocks(buffer, new Piece(8, O)));
    }
}